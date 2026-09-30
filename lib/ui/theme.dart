import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 앱 공통 색
class AppColors {
  static const primary = Color(0xFF12A37F);
  static const primaryDark = Color(0xFF0C7A5F);
  static const mint = Color(0xFFE8F6F1);
  static const capsule = Color(0xFFCFF2E6);
  static const bg = Color(0xFFF7F8F7);
  static const ink = Color(0xFF1F2A28);
  static const sub = Color(0xFF6B7773);
  static const coral = Color(0xFFFF7A6B);
  static const yellow = Color(0xFFFFC857);
  static const line = Color(0xFFE6EBE9);
}

const kAppName = '아이약콕';
const kAppTagline = '우리 아이 약, 나이에 맞는지 콕 확인';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: AppColors.line),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// 앱 심볼: 웃는 캡슐 캐릭터 + 체크 배지 (아이약콕)
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28)),
        Paint()..color = AppColors.primary);

    // 캡슐 (살짝 기울임)
    canvas.save();
    canvas.translate(s * 0.47, s * 0.48);
    canvas.rotate(-math.pi / 6);
    final w = s * 0.62, h = s * 0.32;
    final capsule = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Radius.circular(h / 2));
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-w / 2, -h / 2, 0, h / 2));
    canvas.drawRRect(capsule, Paint()..color = Colors.white);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, -h / 2, w / 2, h / 2));
    canvas.drawRRect(capsule, Paint()..color = AppColors.capsule);
    canvas.restore();

    // 얼굴 (흰 쪽)
    final face = Offset(-w / 4, 0);
    final ink = Paint()..color = AppColors.ink;
    canvas.drawCircle(face + Offset(-s * 0.05, -s * 0.025), s * 0.022, ink);
    canvas.drawCircle(face + Offset(s * 0.05, -s * 0.025), s * 0.022, ink);
    canvas.drawArc(
      Rect.fromCircle(center: face + Offset(0, s * 0.0), radius: s * 0.045),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..strokeCap = StrokeCap.round,
    );
    // 볼터치
    final blush = Paint()..color = AppColors.coral.withAlpha(110);
    canvas.drawCircle(face + Offset(-s * 0.085, s * 0.02), s * 0.018, blush);
    canvas.drawCircle(face + Offset(s * 0.085, s * 0.02), s * 0.018, blush);
    canvas.restore();

    // 체크 배지
    final c = Offset(s * 0.74, s * 0.74);
    canvas.drawCircle(c, s * 0.15, Paint()..color = AppColors.primary);
    canvas.drawCircle(c, s * 0.125, Paint()..color = AppColors.yellow);
    final check = Path()
      ..moveTo(c.dx - s * 0.055, c.dy)
      ..lineTo(c.dx - s * 0.012, c.dy + s * 0.043)
      ..lineTo(c.dx + s * 0.062, c.dy - s * 0.045);
    canvas.drawPath(
        check,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.035
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 섹션 제목
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
