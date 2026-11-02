import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_logo.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';

/// Decides where to send someone on cold start: onboarding, sign-in, or home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    // Long enough to read the wordmark, not long enough to be a wait.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final auth = context.read<AuthProvider>();

    // The session is restored by supabase_flutter before runApp, but the
    // profile row may still be loading, so wait for a settled status rather
    // than routing on `unknown`.
    var waited = 0;
    while (auth.status == AuthStatus.unknown && waited < 4000) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited += 100;
      if (!mounted) return;
    }

    if (!mounted) return;

    if (auth.isSignedIn) {
      if (auth.user != null && !auth.user!.isEmailVerified) {
        final email = Uri.encodeComponent(auth.email ?? '');
        context.go('${AppConstants.routeOtp}?email=$email');
        return;
      }
      context.go(landingRouteFor(auth.user));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
    if (!mounted) return;

    context.go(seenOnboarding
        ? AppConstants.routeLogin
        : AppConstants.routeOnboarding);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: colors.primaryGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const EduxfairLogo(
                size: 96,
                borderRadius: 24,
              )
                  .animate()
                  .scale(duration: 500.ms, curve: Curves.easeOutBack)
                  .fadeIn(duration: 400.ms),
              const SizedBox(height: 24),
              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ).animate(delay: 200.ms).fadeIn(duration: 400.ms).slideY(begin: 0.3),
              const SizedBox(height: 8),
              Text(
                AppConstants.appTagline,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
              ).animate(delay: 350.ms).fadeIn(duration: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
