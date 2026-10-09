import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/dur_api.dart';
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
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _slow = true);
    });
    Future.wait([Future.delayed(const Duration(seconds: 2)), _cleanStorage()]).then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    });
  }

  /// 정리가 오래 걸리면 안내를 보여준다
  bool _slow = false;

  /// 예전 버전이 설정 저장소에 쌓아 둔 큰 식약처 조회 결과를 먼저 지운다.
  /// 이걸 남겨 두면 저장된 기록을 읽을 때 전부 함께 읽느라 앱이 흰 화면에서 멈춘다.
  /// 조회 결과는 이제 임시 파일로 보관한다.
  static Future<void> _cleanStorage() async {
    try {
      await const MethodChannel('pillsafe/prefs')
          .invokeMethod<int>('dropPrefix', {'prefix': DurApi.legacyCachePrefix})
          .timeout(const Duration(seconds: 60));
    } catch (_) {}
    DurApi.pruneCache();
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
              AnimatedOpacity(
                opacity: _slow ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: const Column(children: [
                  SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                  SizedBox(height: 10),
                  Text('저장된 자료를 정리하고 있어요',
                      style: TextStyle(fontSize: 13, color: AppColors.sub)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
