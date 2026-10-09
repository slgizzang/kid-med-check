import 'package:flutter/material.dart';

import '../logic/models.dart';
import 'theme.dart';

/// 메인 화면: 이 복용자의 모든 기록을 모아 본 안전 요약 (지난 확인 결과 기준)
class SafetySummaryCard extends StatelessWidget {
  const SafetySummaryCard({
    super.key,
    required this.records,
    required this.person,
    this.recallCount = 0,
    this.letterCount = 0,
    this.onOpen,
  });

  final List<MedRecord> records;
  final ChildProfile person;
  final int recallCount;
  final int letterCount;

  /// 금기가 있는 기록을 누르면 연다
  final ValueChanged<MedRecord>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final checked = [for (final r in records) if (r.last != null && r.last!.matches(r.drugs)) r];
    final unchecked = records.length - checked.length;
    final age = <MedRecord>[], mix = <MedRecord>[], preg = <MedRecord>[], allergy = <MedRecord>[];
    var ageN = 0, mixN = 0, pregN = 0, allergyN = 0;
    for (final r in checked) {
      final s = r.last!;
      final a = s.drugs.where((d) => d.ageRule != null).length;
      final p = s.drugs.where((d) => d.preg).length;
      final al = s.drugs.where((d) => d.allergy != null).length;
      if (a > 0) {
        age.add(r);
        ageN += a;
      }
      if (s.mixPairs.isNotEmpty) {
        mix.add(r);
        mixN += s.mixPairs.length;
      }
      if (p > 0) {
        preg.add(r);
        pregN += p;
      }
      if (al > 0) {
        allergy.add(r);
        allergyN += al;
      }
    }
    final lines = <Widget>[
      _line('연령금기', ageN, age, unit: '개'),
      _line('병용금기(함께 먹으면 안 되는 조합)', mixN, mix, unit: '쌍'),
      if (person.pregnant) _line('임부금기', pregN, preg, unit: '개'),
      if (person.allergies.isNotEmpty) _line('알레르기 약물과 같은 성분', allergyN, allergy, unit: '개'),
      _line('회수된 약', recallCount, const [], unit: '건'),
      _line('식약처 주의 알림', letterCount, const [], unit: '건', soft: true),
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: KText('전체 기록 안전 요약 · ${records.length}건',
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
        ]),
        const SizedBox(height: 8),
        ...lines,
        if (unchecked > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: KText(
                '아직 안전 확인을 하지 않았거나 약이 바뀐 기록 $unchecked건은 빠져 있어요. 기록을 열어 안전 확인을 눌러주세요.',
                flow: true,
                style: const TextStyle(fontSize: 12, color: AppColors.sub, height: 1.45)),
          ),
      ]),
    );
  }

  Widget _line(String label, int n, List<MedRecord> recs, {required String unit, bool soft = false}) {
    final ok = n == 0;
    final fg = ok
        ? const Color(0xFF1E7B3A)
        : soft
            ? const Color(0xFF9A3412)
            : const Color(0xFFC62828);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle : (soft ? Icons.info : Icons.error), size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: KText(ok ? '$label 없음' : '$label $n$unit',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
          ),
        ]),
        for (final r in recs.take(3))
          InkWell(
            onTap: onOpen == null ? null : () => onOpen!(r),
            child: Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Row(children: [
                Expanded(
                  child: KText(r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.sub)),
                ),
                if (onOpen != null) const Icon(Icons.chevron_right, size: 18, color: AppColors.sub),
              ]),
            ),
          ),
      ]),
    );
  }
}
