import 'package:flutter/material.dart';

import '../logic/recall.dart';
import 'theme.dart';

/// 복용 기록 중 회수된 약 안내 (첫 화면·기록 화면 공용)
class RecallCard extends StatelessWidget {
  const RecallCard({super.key, required this.hits, this.onOpen, this.showRecord = false});

  final List<RecallHit> hits;

  /// 누르면 그 기록을 연다 (첫 화면)
  final ValueChanged<RecallHit>? onOpen;

  /// 어느 기록의 약인지 함께 보여줄지
  final bool showRecord;

  static const _fg = Color(0xFFB71C1C);
  static const _bg = Color(0xFFFDECEC);

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.campaign_outlined, color: _fg, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: KText('회수된 약이 있어요 · ${hits.length}건',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _fg)),
          ),
        ]),
        const SizedBox(height: 4),
        const KText('식약처 회수·판매중지 정보에 먹은 약과 같은 제품이 올라왔어요.',
            flow: true, style: TextStyle(fontSize: 12.5, color: _fg, height: 1.45)),
        for (final h in hits.take(5))
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
                  if (onOpen != null) const Icon(Icons.chevron_right, size: 20, color: _fg),
                ]),
                KText(
                    [
                      if (showRecord) recallRecordLabel(h.record),
                      '${recallDateLabel(h.recall.date)} ${h.recall.forced ? '회수 명령' : '자진 회수'}',
                      if (h.recall.company.isNotEmpty) h.recall.company,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                const SizedBox(height: 4),
                KText(recallAdvice(h.recall),
                    flow: true, style: const TextStyle(fontSize: 13, color: _fg, height: 1.45)),
              ]),
            ),
          ),
        if (hits.length > 5)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KText('외 ${hits.length - 5}건', style: const TextStyle(fontSize: 12, color: _fg)),
          ),
      ]),
    );
  }
}
