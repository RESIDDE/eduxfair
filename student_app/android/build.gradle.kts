allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Some plugins (file_picker 8.x) hard-code compileSdk 34, but
// flutter_plugin_android_lifecycle requires 36 of everything that depends on
// it. compileSdk only decides which APIs a library compiles against, not
// runtime behaviour, so lifting every plugin to the app's level is safe.
// finalizeDsl runs after the plugin's own script but before AGP locks the
// DSL (an afterEvaluate is too late under AGP 9).
//
// smart_auth (pulled in by pinput 3.x) gets 34 instead: its Kotlin is not
// null-safe against the API 36 stubs, and its androidx deps need only 34.
val pluginCompileSdkOverride = mapOf("smart_auth" to 34)
subprojects {
    val target = pluginCompileSdkOverride[name] ?: 36
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {
            finalizeDsl { android ->
                if ((android.compileSdk ?: 0) < target) android.compileSdk = target
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
