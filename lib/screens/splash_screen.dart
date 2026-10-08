import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'home_screen.dart';

/// 앱을 켤 때 2초 동안 로고와 소개 문구를 보여준 뒤 홈으로
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
    ..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(fade),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppLogo(size: 96),
              const SizedBox(height: 22),
              const Text(kAppName,
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: AppColors.ink)),
              const SizedBox(height: 6),
              const Text(kAppSlogan,
                  style: TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand)),
              const SizedBox(height: 28),
              Text(kAppTagline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AppColors.sub, height: 1.5)),
            ]),
          ),
        ),
      ),
    );
  }
}
