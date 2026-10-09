import 'package:flutter/material.dart';

import '../logic/models.dart';
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
          title: '회수된 약 · ${home.length}건',
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

/// 식약처 주의 알림(안전성 서한)이 있었던 약 — 첫 화면 안내 (회수 안내와 같은 모양)
class LetterHit {
  LetterHit(this.record, this.drug);
  final MedRecord record;
  final String drug;
}

/// 기록들에서 안전성 서한 표시가 있는 약 (같은 약은 가장 최근 기록 하나만)
List<LetterHit> letterHits(List<MedRecord> records) {
  final byDrug = <String, LetterHit>{};
  final sorted = [...records]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final r in sorted) {
    for (final d in r.drugs) {
      if (r.safetyLetters.containsKey(d)) byDrug.putIfAbsent(d, () => LetterHit(r, d));
    }
  }
  return byDrug.values.toList();
}

class LetterCard extends StatelessWidget {
  const LetterCard({super.key, required this.hits, this.onOpen});
  final List<LetterHit> hits;
  final ValueChanged<LetterHit>? onOpen;

  static const _fg = Color(0xFF9A3412);
  static const _bg = Color(0xFFFFF4E8);

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
          const Icon(Icons.info_outline, color: _fg, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: KText('식약처 주의 알림이 있었던 약 · ${hits.length}건',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _fg)),
          ),
        ]),
        const SizedBox(height: 4),
        const KText(
            '식약처가 의사·약사에게 처방할 때 주의하라고 알린(안전성 서한) 약이에요. 먹으면 안 된다는 뜻은 아니에요.',
            flow: true,
            style: TextStyle(fontSize: 12.5, color: _fg, height: 1.45)),
        for (final h in hits.take(5))
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onOpen == null ? null : () => onOpen!(h),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    KText(h.drug,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                    KText(recallRecordLabel(h.record),
                        style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                  ]),
                ),
                if (onOpen != null) const Icon(Icons.chevron_right, size: 20, color: _fg),
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

/// 회수된 약 / 주의 알림 상세 화면
class AlertListScreen extends StatelessWidget {
  const AlertListScreen({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: KText(title, maxLines: 1)),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 40), children: [child]),
      );
}
