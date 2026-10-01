import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 앱 공통 색
class AppColors {
  /// 심볼 배경색 (깊은 초록)
  static const brand = Color(0xFF0E8F6E);
  static const primary = Color(0xFF0E9A76);
  static const primaryDark = Color(0xFF0A6F55);
  static const mint = Color(0xFFE9F5F0);
  static const capsule = Color(0xFFCFF2E6);
  static const bg = Color(0xFFF5F6F8);
  static const ink = Color(0xFF191F28);
  static const sub = Color(0xFF6B7684);
  static const coral = Color(0xFFFF7A6B);
  static const yellow = Color(0xFFFFC857);
  static const line = Color(0xFFE8EBEE);
}

const kAppName = '아이약콕';
const kAppTagline = '우리 아이 약, 안전한지 콕 확인';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Pretendard',
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
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

/// 앱 심볼: 캡슐 약 + "콕" 눌러 확인하는 체크 (아이약콕). 런처 아이콘과 같은 모양.
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
    final k = size.width / 1024;
    Offset p(double x, double y) => Offset(x * k, y * k);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.23)),
        Paint()..color = AppColors.brand);

    // 캡슐 (/ 방향으로 45도)
    canvas.save();
    canvas.translate(430 * k, 600 * k);
    canvas.rotate(-math.pi / 4);
    final w = 540 * k, h = 230 * k;
    final capsule = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h / 2));
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-w / 2, -h / 2, 0, h / 2));
    canvas.drawRRect(capsule, Paint()..color = Colors.white);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, -h / 2, w / 2, h / 2));
    canvas.drawRRect(capsule, Paint()..color = const Color(0xFFBFEBDD));
    canvas.restore();
    canvas.restore();

    // "콕" 파동
    final t = p(716, 312);
    for (final (r, a) in [(198.0, 105), (138.0, 195)]) {
      canvas.drawArc(
        Rect.fromCircle(center: t, radius: r * k),
        232 * math.pi / 180,
        166 * math.pi / 180,
        false,
        Paint()
          ..color = Colors.white.withAlpha(a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24 * k,
      );
    }
    // 확인 체크
    canvas.drawCircle(t, 80 * k, Paint()..color = AppColors.yellow);
    canvas.drawPath(
      Path()
        ..moveTo(t.dx - 36 * k, t.dy + 2 * k)
        ..lineTo(t.dx - 9 * k, t.dy + 29 * k)
        ..lineTo(t.dx + 38 * k, t.dy - 26 * k),
      Paint()
        ..color = AppColors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22 * k
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
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
          child: Text(ka(text),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// 한글이 단어 중간에서 줄바꿈되지 않게 한다 (CSS의 word-break: keep-all).
/// 단어 안 글자 사이에 '단어 결합자(U+2060)'를 넣어 띄어쓰기에서만 줄이 바뀌게 한다.
String ka(String text) {
  const joiner = '⁠';
  return text
      .split(' ')
      .map((w) => w.characters.join(joiner))
      .join(' ');
}

/// 문장이 여러 개면 문장마다 줄을 바꾼다 ("… 확인하세요. 의사가 …" → 두 줄)
String splitSentences(String text) =>
    text.replaceAllMapped(RegExp(r'([.?!。])\s+(?=[가-힣"“(])'), (m) => '${m[1]}\n');

/// Text와 같지만 읽기 좋게 줄바꿈한다.
/// 1) 한글 단어 중간에서 끊지 않고  2) 문장마다 새 줄로  3) 줄 길이를 고르게 맞춰
///    마지막 줄에 단어 하나만 덩그러니 남지 않게 한다 (CSS text-wrap: balance).
class KText extends StatelessWidget {
  const KText(this.data,
      {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final text = ka(maxLines == 1 ? data : splitSentences(data));
    final plain = Text(text,
        style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow);
    if (maxLines == 1) return plain;
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final align = switch (textAlign) {
      TextAlign.center => 0.5,
      TextAlign.right || TextAlign.end => 1.0,
      _ => 0.0,
    };
    return _Balanced(
      span: TextSpan(text: text, style: effective),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: maxLines,
      align: align,
      child: plain,
    );
  }
}

class _Balanced extends SingleChildRenderObjectWidget {
  const _Balanced({
    required this.span,
    required this.textScaler,
    required this.maxLines,
    required this.align,
    required super.child,
  });

  final InlineSpan span;
  final TextScaler textScaler;
  final int? maxLines;
  final double align;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBalanced(span, textScaler, maxLines, align);

  @override
  void updateRenderObject(BuildContext context, _RenderBalanced r) {
    r
      ..span = span
      ..textScaler = textScaler
      ..maxLines = maxLines
      ..align = align
      ..markNeedsLayout();
  }
}

class _RenderBalanced extends RenderShiftedBox {
  _RenderBalanced(this.span, this.textScaler, this.maxLines, this.align) : super(null);

  InlineSpan span;
  TextScaler textScaler;
  int? maxLines;
  double align;

  int _lines(double w) {
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: w);
    final n = tp.computeLineMetrics().length;
    tp.dispose();
    return n;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints c) {
    final kid = child;
    if (kid == null) return c.smallest;
    return c.constrain(kid.getDryLayout(BoxConstraints(
        minWidth: 0, maxWidth: c.maxWidth, minHeight: c.minHeight, maxHeight: c.maxHeight)));
  }

  @override
  void performLayout() {
    final c = constraints;
    final kid = child;
    if (kid == null) {
      size = c.smallest;
      return;
    }
    var w = c.maxWidth;
    if (w.isFinite && w > 0) {
      final full = _lines(w);
      if (full > 1) {
        var lo = w * 0.5, hi = w;
        for (var i = 0; i < 10; i++) {
          final mid = (lo + hi) / 2;
          if (_lines(mid) <= full) {
            hi = mid;
          } else {
            lo = mid;
          }
        }
        w = (hi + 1).clamp(0.0, c.maxWidth);
      }
    }
    kid.layout(
      BoxConstraints(
          minWidth: 0, maxWidth: w, minHeight: c.minHeight, maxHeight: c.maxHeight),
      parentUsesSize: true,
    );
    size = c.constrain(kid.size);
    (kid.parentData! as BoxParentData).offset =
        Offset((size.width - kid.size.width) * align, 0);
  }
}
