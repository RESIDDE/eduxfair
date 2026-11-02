import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

/// Explains the three ideas that make the product different, in the order a
/// student cares about them: build it once, get approached, meet and apply.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.badge_rounded,
      title: 'One passport,\nevery institution',
      body: 'Build your Education Passport once — your qualifications, grades '
          'and documents. Never explain them at a seventh booth again.',
    ),
    _OnboardingPage(
      icon: Icons.handshake_rounded,
      title: 'Let institutions\ncome to you',
      body: 'Universities see that someone with your profile matches their '
          'programs, and reach out. They only learn who you are when you '
          'choose to share.',
    ),
    _OnboardingPage(
      icon: Icons.qr_code_2_rounded,
      title: 'Your fair,\nin your pocket',
      body: 'Tap to connect at any booth. Afterwards, get a report of every '
          'institution you met and every program that matched.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (!mounted) return;
    context.go(AppConstants.routeSignup);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 8),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: colors.accentGradient,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(page.icon, size: 36, color: context.colors.onAccent),
                        ),
                        const SizedBox(height: 32),
                        Text(page.title, style: text.displaySmall),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          style: text.bodyLarge?.copyWith(
                            color: colors.textSecondary,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Column(
                children: [
                  SmoothPageIndicator(
                    controller: _controller,
                    count: _pages.length,
                    effect: ExpandingDotsEffect(
                      dotHeight: 8,
                      dotWidth: 8,
                      expansionFactor: 3,
                      activeDotColor: colors.accent,
                      dotColor: colors.border,
                    ),
                  ),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: () {
                      if (isLast) {
                        _finish();
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Text(isLast ? 'Create my passport' : 'Next'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(AppConstants.routeLogin),
                    child: const Text('I already have an account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
