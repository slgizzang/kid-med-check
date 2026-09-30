import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 앱 공통 색
class AppColors {
  static const primary = Color(0xFF14866D);
  static const primaryDark = Color(0xFF0B5E4C);
  static const mint = Color(0xFFE3F4EE);
  static const bg = Color(0xFFF5F8F7);
  static const ink = Color(0xFF1B2A26);
  static const sub = Color(0xFF5E706B);
  static const coral = Color(0xFFFF7A6B);
  static const line = Color(0xFFE2EAE7);
}

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

/// 앱 심볼: 둥근 사각형 + 방패 + 캡슐
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

    // 배경
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2BB594), Color(0xFF0B6E58)],
      ).createShader(rect);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * 0.26)), bg);

    // 방패
    final shield = Path()
      ..moveTo(s * 0.5, s * 0.16)
      ..quadraticBezierTo(s * 0.66, s * 0.24, s * 0.8, s * 0.24)
      ..lineTo(s * 0.8, s * 0.48)
      ..quadraticBezierTo(s * 0.8, s * 0.72, s * 0.5, s * 0.86)
      ..quadraticBezierTo(s * 0.2, s * 0.72, s * 0.2, s * 0.48)
      ..lineTo(s * 0.2, s * 0.24)
      ..quadraticBezierTo(s * 0.34, s * 0.24, s * 0.5, s * 0.16)
      ..close();
    canvas.drawPath(shield, Paint()..color = Colors.white);

    // 캡슐 (기울임)
    canvas.save();
    canvas.translate(s * 0.5, s * 0.5);
    canvas.rotate(-math.pi / 4);
    final w = s * 0.40, h = s * 0.17;
    final capsule = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Radius.circular(h / 2));
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-w / 2, -h / 2, 0, h / 2));
    canvas.drawRRect(capsule, Paint()..color = AppColors.coral);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, -h / 2, w / 2, h / 2));
    canvas.drawRRect(capsule, Paint()..color = const Color(0xFF2BB594));
    canvas.restore();
    canvas.restore();
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
