import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

class _Slide {
  const _Slide(this.image, this.background, this.title, this.body);

  final String image;
  final Color background;
  final String title;
  final String body;
}

const List<_Slide> _slides = [
  _Slide(
    'assets/onboarding/onboarding-1.png',
    AppColors.primarySoft,
    'Take every kind of payment',
    'Lightning, card, bank transfer or cash. Type the amount and let the customer scan.',
  ),
  _Slide(
    'assets/onboarding/onboarding-2.png',
    AppColors.bitcoinSoft,
    'Bitcoin straight to your wallet',
    'Connect your own Lightning wallet. We never hold your sats, and you see the moment a payment lands.',
  ),
  _Slide(
    'assets/onboarding/onboarding-3.png',
    AppColors.purpleSoft,
    'Sell airtime, data and bills',
    'Top up your float once, then vend airtime, data, TV and electricity all day.',
  ),
];

/// Three illustrated pages shown the first time the app is opened.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final PageController _pages = PageController();
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);
  int _index = 0;

  bool get _last => _index == _slides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    _float.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      widget.onDone();
    } else {
      _pages.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset('assets/brand/logo.png', width: 34, height: 34),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Oja POS',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _last ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _last ? null : widget.onDone,
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final slide = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _float,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(0, -10 * Curves.easeInOut.transform(_float.value)),
                                child: child,
                              ),
                              child: Image.asset(
                                slide.image,
                                fit: BoxFit.contain,
                                semanticLabel: slide.title,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted, fontSize: 16, height: 1.45),
                        ),
                        const SizedBox(height: 28),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.primary : AppColors.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: PrimaryButton(
                label: _last ? 'Get started' : 'Next',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
