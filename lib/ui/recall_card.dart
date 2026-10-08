import 'package:flutter/material.dart';

import '../logic/recall.dart';
import 'theme.dart';

/// 복용 기록 중 회수된 약 안내 (첫 화면·기록 화면 공용).
/// 집에 남아 있을 수 있는 약은 빨간 안내, 이미 맞은 주사는 회색의 조용한 안내.
class RecallCard extends StatelessWidget {
  const RecallCard({super.key, required this.hits, this.onOpen, this.showRecord = false});

  final List<RecallHit> hits;

  /// 누르면 그 기록을 연다 (첫 화면)
  final ValueChanged<RecallHit>? onOpen;

  /// 어느 기록의 약인지 함께 보여줄지
  final bool showRecord;

  @override
  Widget build(BuildContext context) {
    final home = hits.where((h) => !h.injected).toList();
    final shots = hits.where((h) => h.injected).toList();
    return Column(children: [
      if (home.isNotEmpty)
        _box(
          fg: const Color(0xFFB71C1C),
          bg: const Color(0xFFFDECEC),
          icon: Icons.campaign_outlined,
          title: '회수된 약이 있어요 · ${home.length}건',
          sub: '식약처 회수·판매중지 정보에 처방/구매한 제품이 올라왔어요.',
          items: home,
          advice: recallAdvice,
        ),
      if (shots.isNotEmpty)
        _box(
          fg: const Color(0xFF334155),
          bg: const Color(0xFFF1F4F8),
          icon: Icons.info_outline,
          title: '이미 맞은 주사가 회수됐어요 · ${shots.length}건',
          sub: '식약처 회수·판매중지 정보에 병원에서 맞은 주사와 같은 제품이 올라왔어요.',
          items: shots,
          advice: injectedRecallAdvice,
        ),
    ]);
  }

  Widget _box({
    required Color fg,
    required Color bg,
    required IconData icon,
    required String title,
    required String sub,
    required List<RecallHit> items,
    required String Function(Recall) advice,
  }) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: KText(title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
            ),
          ]),
          const SizedBox(height: 4),
          KText(sub, flow: true, style: TextStyle(fontSize: 12.5, color: fg, height: 1.45)),
          for (final h in items.take(5))
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onOpen == null ? null : () => onOpen!(h),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: KText(h.drug,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                    ),
                    if (onOpen != null) Icon(Icons.chevron_right, size: 20, color: fg),
                  ]),
                  KText(
                      [
                        if (showRecord) recallRecordLabel(h.record),
                        '${recallDateLabel(h.recall.date)} ${h.recall.forced ? '회수 명령' : '자진 회수'}',
                        if (h.recall.company.isNotEmpty) h.recall.company,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                  const SizedBox(height: 4),
                  KText(advice(h.recall),
                      flow: true, style: TextStyle(fontSize: 13, color: fg, height: 1.45)),
                ]),
              ),
            ),
          if (items.length > 5)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KText('외 ${items.length - 5}건', style: TextStyle(fontSize: 12, color: fg)),
            ),
        ]),
      );
}
