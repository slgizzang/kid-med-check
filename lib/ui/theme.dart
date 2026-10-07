import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 앱 공통 색
class AppColors {
  /// 심볼·안전(문제 없음) 표시에만 쓰는 청록
  static const brand = Color(0xFF0E8F6E);
  static const brandTint = Color(0xFFE5F3EE);

  /// 버튼·선택 등 화면 기본 색: 심볼 청록을 조금 깊게 (흰 글자가 또렷하게)
  /// 넓은 면은 흰색·밝은 회색으로 두고, 이 색은 버튼·선택 테두리처럼 작은 곳에만 쓴다.
  static const primary = Color(0xFF0B7D62);
  static const onPrimary = Colors.white;

  /// 아주 연한 청록 (작은 배지·칩 배경)
  static const primarySoft = Color(0xFFE8F4EF);

  /// 글자 버튼·링크용 짙은 청록
  static const primaryDark = Color(0xFF08654F);

  /// 안내 상자 배경 (중립 회색)
  static const mint = Color(0xFFF2F4F6);
  static const capsule = Color(0xFFCFF2E6);
  static const bg = Color(0xFFF6F7F9);
  static const ink = Color(0xFF191F28);
  static const sub = Color(0xFF6B7684);
  static const coral = Color(0xFFFF7A6B);
  static const yellow = Color(0xFFFFC857);
  static const line = Color(0xFFE8EBEE);
}

const kAppName = '필세이프';

/// 실손24 청구 안내 (네이버 지도·토스 연계가 열리면 true로 다시 켠다).
/// 관련 화면: 복용 기록의 '실손24로 청구하기' 버튼·청구 완료 체크, 리포트의 '실손보험 청구 확인'.
const kShowSilson24 = true;

/// 영문 슬로건 (pill ↔ feel)
const kAppSlogan = 'My pill safe, I feel safe';
const kAppTagline = '약 조회부터 안전 확인, 실손 청구까지';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
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
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryDark,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
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

/// 사람마다 다른 파스텔 색 (아바타·아이콘 칩). (배경, 글자)
const kPastels = <(Color, Color)>[
  (Color(0xFFFFEDE2), Color(0xFFC2561C)), // 살구
  (Color(0xFFE6EFFF), Color(0xFF2F5FBF)), // 하늘
  (Color(0xFFEFEAFD), Color(0xFF6448C2)), // 라벤더
  (Color(0xFFE3F4EE), Color(0xFF0B7D62)), // 민트
  (Color(0xFFFDE8F0), Color(0xFFB4386A)), // 로즈
];

const kPastelTeal = (Color(0xFFE3F4EE), Color(0xFF0B7D62));
const kPastelSky = (Color(0xFFE6EFFF), Color(0xFF2F5FBF));
const kPastelLavender = (Color(0xFFEFEAFD), Color(0xFF6448C2));

(Color, Color) pastelFor(String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return kPastels[h % kPastels.length];
}

/// 앱 심볼: 두 고리가 이어진 캡슐 — "약 정보를 잇는다". 런처 아이콘과 같은 모양.
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
  // 1024 기준 크기 (런처 아이콘 생성과 같은 값)
  static const _l = 700.0, _h = 290.0, _g = 45.0, _d = 40.0, _w = 72.0;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1024;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.23)),
        Paint()..color = AppColors.brand);
    const r = _h / 2;
    final path = Path()
      ..moveTo(-_g, -r)
      ..lineTo(-_l / 2 + r, -r)
      ..arcTo(Rect.fromCircle(center: const Offset(-_l / 2 + r, 0), radius: r), -math.pi / 2,
          -math.pi, false)
      ..lineTo(-_d, r)
      ..lineTo(_d, -r)
      ..lineTo(_l / 2 - r, -r)
      ..arcTo(Rect.fromCircle(center: const Offset(_l / 2 - r, 0), radius: r), -math.pi / 2,
          math.pi, false)
      ..lineTo(_g, r);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    canvas.rotate(-28 * math.pi / 180);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = _w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // 왼쪽 위 작은 십자 (병원·의료 표시). 런처 아이콘과 같은 위치·크기.
    const cx = 272.0, cy = 282.0, arm = 74.0, th = 50.0;
    final cross = Paint()..color = Colors.white;
    final rr = Radius.circular(th / 2 * 0.6 * k);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB((cx - arm) * k, (cy - th / 2) * k, (cx + arm) * k, (cy + th / 2) * k),
            rr),
        cross);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB((cx - th / 2) * k, (cy - arm) * k, (cx + th / 2) * k, (cy + arm) * k),
            rr),
        cross);
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
      {super.key, this.style, this.textAlign, this.maxLines, this.overflow, this.flow = false});

  /// true면 문장마다 줄을 나누지 않고 이어 쓴다 (줄이 바뀔 때 단어는 끊지 않음)
  final bool flow;

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final text = ka(maxLines == 1 || flow ? data : splitSentences(data));
    final plain = Text(text,
        style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow);
    if (maxLines == 1 || flow) return plain;
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
