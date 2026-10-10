import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/recall.dart' show recallRecordLabel;
import 'dashboard.dart' show SafetyTiles;
import 'theme.dart';

/// 메인 화면: 이 복용자의 모든 기록을 모아 본 안전 요약 (지난 확인 결과 기준)
class SafetySummaryCard extends StatelessWidget {
  const SafetySummaryCard({
    super.key,
    required this.records,
    required this.person,
    this.recallCount = 0,
    this.letterCount = 0,
    this.recallRecords = const [],
    this.letterRecords = const [],
    this.onOpen,
    this.onOpenRecalls,
    this.onOpenLetters,
    this.checking = 0,
  });

  /// 회수된 약 / 주의 알림 상세 화면 열기
  final VoidCallback? onOpenRecalls;
  final VoidCallback? onOpenLetters;

  /// 자동 안전 확인이 남은 기록 수 (0이면 모두 확인됨)
  final int checking;

  final List<MedRecord> records;
  final ChildProfile person;
  final int recallCount;
  final int letterCount;

  /// 회수된 약 / 주의 알림이 있는 기록과 해당 약 이름 (누르면 그 기록의 안전 확인 결과로)
  final List<(MedRecord, String)> recallRecords;
  final List<(MedRecord, String)> letterRecords;

  /// 금기가 있는 기록을 누르면 연다
  final ValueChanged<MedRecord>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final checked = [for (final r in records) if (r.last != null && r.last!.matches(r.drugs)) r];
    // 항목마다 (기록, 해당 약) 목록
    final age = <(MedRecord, String)>[], mix = <(MedRecord, String)>[];
    final preg = <(MedRecord, String)>[], allergy = <(MedRecord, String)>[];
    var ageN = 0, mixN = 0, pregN = 0, allergyN = 0;
    for (final r in checked) {
      final s = r.last!;
      final a = [for (final d in s.drugs) if (d.ageRule != null) d.title];
      final p = [
        for (final d in s.drugs)
          if ((d.preg && person.pregnant) || (d.nursing && person.nursing)) d.title
      ];
      final al = [for (final d in s.drugs) if (d.allergy != null) d.title];
      if (a.isNotEmpty) {
        age.add((r, a.join(', ')));
        ageN += a.length;
      }
      if (s.mixPairs.isNotEmpty) {
        mix.add((r, s.mixPairs.join(' / ')));
        mixN += s.mixPairs.length;
      }
      if (p.isNotEmpty) {
        preg.add((r, p.join(', ')));
        pregN += p.length;
      }
      if (al.isNotEmpty && person.allergies.isNotEmpty) {
        allergy.add((r, al.join(', ')));
        allergyN += al.length;
      }
    }
    // 수유부 주의만 있으면 금기가 아니라 주의(주황)로 본다
    final hard = ageN + mixN + (person.pregnant ? pregN : 0) + allergyN;
    final issues = hard + letterCount + recallCount + (person.pregnant ? 0 : pregN);
    final busy = checking > 0;
    // 결론 한 줄: 문제가 있으면 그 항목만, 없으면 '문제없어요'
    final IconData icon;
    final Color fg;
    final String head;
    final String sub;
    if (issues > 0) {
      icon = hard > 0 ? Icons.error : Icons.info;
      fg = hard > 0 ? const Color(0xFFC62828) : const Color(0xFF9A3412);
      head = '확인할 약이 $issues건 있어요';
      sub = '아래 기록을 누르면 자세한 내용을 볼 수 있어요';
    } else if (checked.isEmpty) {
      icon = Icons.hourglass_top_rounded;
      fg = AppColors.sub;
      head = busy ? '안전 확인 중이에요' : '아직 확인한 기록이 없어요';
      sub = busy ? '잠시만 기다려 주세요' : '인터넷 연결을 확인한 뒤 앱을 다시 열어주세요';
    } else {
      icon = Icons.check_circle;
      fg = const Color(0xFF1E7B3A);
      head = '문제없어요';
      sub = '확인한 기록 ${checked.length}건 모두 금기·회수된 약 없음';
    }
    final lines = <Widget>[
      if (ageN > 0) _line('연령금기', ageN, age, unit: '개'),
      if (mixN > 0) _line('함께 먹으면 안 되는 조합', mixN, mix, unit: '쌍'),
      if (pregN > 0) _line('임부·수유부 금기', pregN, preg, unit: '개', soft: !person.pregnant),
      if (allergyN > 0) _line('알레르기 약물과 같은 성분', allergyN, allergy, unit: '개'),
      if (recallCount > 0) _line('회수된 약', recallCount, recallRecords, unit: '건', soft: true),
      if (letterCount > 0)
        _line('식약처 주의 알림이 있었던 약', letterCount, letterRecords, unit: '건', soft: true),
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
        KText('${person.name}님 약 안전 점검',
            maxLines: 1,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub)),
        const SizedBox(height: 6),
        Row(children: [
          Icon(icon, color: fg, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: KText(head,
                maxLines: 1,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: fg)),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 34, top: 2),
          child: KText(sub, style: const TextStyle(fontSize: 12.5, color: AppColors.sub)),
        ),
        // 전체 기록 대시보드 (안전 확인 결과 화면과 같은 구성)
        if (checked.isNotEmpty) ...[
          const SizedBox(height: 12),
          SafetyTiles(
            age: ageN,
            preg: pregN,
            pregApplicable: person.pregnant || person.nursing,
            pregSoft: !person.pregnant,
            mix: mixN,
            recall: recallCount,
            letter: letterCount,
            label: [
              for (final r in checked)
                for (final d in r.last!.drugs)
                  if (d.labelNote != null && !d.isDanger) d
            ].length,
          ),
        ],
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 4),
          ...lines,
        ],
        if (busy && checked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Expanded(
                child: KText('남은 기록 $checking건도 확인하는 중이에요',
                    maxLines: 1, style: const TextStyle(fontSize: 12.5, color: AppColors.sub)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _line(String label, int n, List<(MedRecord, String)> recs,
      {required String unit, bool soft = false, VoidCallback? onTap}) {
    final ok = n == 0;
    final fg = ok
        ? const Color(0xFF1E7B3A)
        : soft
            ? const Color(0xFF9A3412)
            : const Color(0xFFC62828);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onTap,
          child: Row(children: [
            Icon(ok ? Icons.check_circle : (soft ? Icons.info : Icons.error), size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: KText(ok ? '$label 없음' : '$label $n$unit',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
            ),
            if (onTap != null) Icon(Icons.chevron_right, size: 20, color: fg),
          ]),
        ),
        // 해당 기록을 작은 목록으로 모두 (누르면 그 기록의 안전 확인 결과)
        for (final (r, what) in recs)
          InkWell(
            onTap: onOpen == null ? null : () => onOpen!(r),
            child: Padding(
              padding: const EdgeInsets.only(left: 26, top: 3, bottom: 1),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    KText(recallRecordLabel(r),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w600)),
                    KText(what,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                  ]),
                ),
                if (onOpen != null) const Icon(Icons.chevron_right, size: 18, color: AppColors.sub),
              ]),
            ),
          ),
      ]),
    );
  }
}
