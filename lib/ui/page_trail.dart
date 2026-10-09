import 'package:flutter/material.dart';

import 'theme.dart';

/// 지금 어느 화면인지 보여주는 얇은 경로 표시: 전체 기록 › 복용 기록 › 안전 확인 결과
/// 지나온 단계는 눌러서 돌아갈 수 있다.
class PageTrail extends StatelessWidget {
  const PageTrail({super.key, required this.current, this.onDark = false, this.recordLabel = '복용 기록'});

  /// 0 전체 기록(메인) · 1 복용 기록(처방·구입 한 건) · 2 안전 확인 결과
  final int current;

  /// 초록 바탕 위에 놓일 때
  final bool onDark;

  /// 가운데 단계 이름 (약국 구입 기록 등)
  final String recordLabel;

  static const _icons = [Icons.home_outlined, Icons.receipt_long_outlined, Icons.shield_outlined];

  @override
  Widget build(BuildContext context) {
    final labels = ['전체 기록', recordLabel, '안전 확인 결과'];
    final on = onDark ? Colors.white : AppColors.primaryDark;
    final off = onDark ? const Color(0xB3FFFFFF) : AppColors.sub;
    final chipBg = onDark ? const Color(0x2EFFFFFF) : AppColors.primarySoft;

    void go(int i) {
      if (i >= current) return;
      if (i == 0) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        Navigator.of(context).pop();
      }
    }

    final items = <Widget>[];
    for (var i = 0; i <= 2; i++) {
      if (i > 0) {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.chevron_right_rounded, size: 16, color: off),
        ));
      }
      final isNow = i == current;
      final reachable = i < current;
      final upcoming = i > current;
      items.add(Flexible(
        flex: isNow ? 0 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: reachable ? () => go(i) : null,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: isNow ? 10 : 4, vertical: 4),
            decoration: isNow
                ? BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20))
                : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_icons[i], size: 14, color: isNow ? on : off),
              const SizedBox(width: 4),
              Flexible(
                child: Text(labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isNow ? FontWeight.w800 : FontWeight.w500,
                      color: isNow ? on : off.withAlpha(upcoming ? 120 : 255),
                    )),
              ),
            ]),
          ),
        ),
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: items);
  }
}
