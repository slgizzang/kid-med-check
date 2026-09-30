import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/snapshot.dart';
import 'theme.dart';

const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDECEC);
const _orange = Color(0xFFB45309);
const _orangeBg = Color(0xFFFFF4E8);
const _green = Color(0xFF1E7B3A);
const _greenBg = Color(0xFFEAF6EE);

/// 확인 결과 대시보드: 항목별 타일 + 확인이 필요한 약 목록 + 병용금기 조합
class ResultDashboard extends StatelessWidget {
  const ResultDashboard({
    super.key,
    required this.snap,
    required this.person,
    this.stale = false,
    this.showDate = false,
  });

  final ResultSnapshot snap;
  final ChildProfile person;

  /// 목록이 바뀌어 다시 확인해야 함
  final bool stale;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final flagged = snap.drugs.where((d) => d.hasAny).toList();
    final pn = snap.pregnant || snap.nursing;
    final tiles = <Widget>[
      _Tile(label: '연령금기', count: snap.ageCount, icon: Icons.child_care),
      _Tile(
        label: '임부·수유부 금기',
        count: snap.pregCount,
        icon: Icons.pregnant_woman,
        notApplicable: !pn,
      ),
      _Tile(label: '병용금기', count: snap.mixPairs.length, icon: Icons.compare_arrows),
    ];

    return Opacity(
      opacity: stale ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 누구 기준인지
            Row(children: [
              Expanded(
                child: KText('${person.name} · ${formatAge(person.ageInMonths())}',
                    maxLines: 1,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink)),
              ),
              if (snap.pregnant) const _Pill('임신 중'),
              if (snap.nursing) const _Pill('수유 중'),
            ]),
            if (showDate)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: KText('${_dt(snap.at)} 확인 결과',
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12, color: AppColors.sub)),
              ),
            const SizedBox(height: 12),
            // 항목별 타일
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
            const SizedBox(height: 14),
            // 병용금기: 없어도 "없음"을 명시
            _Line(
              ok: snap.mixPairs.isEmpty,
              text: snap.mixPairs.isEmpty
                  ? '목록 안의 약끼리 병용금기 없음'
                  : '병용금기 조합 ${snap.mixPairs.length}개',
            ),
            for (final p in snap.mixPairs)
              Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: KText(p,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
              ),
            if (flagged.isEmpty && snap.pickCount == 0)
              const _Line(ok: true, text: '확인한 약 모두 해당 금기 없음'),
            if (flagged.isNotEmpty) ...[
              const SizedBox(height: 14),
              const KText('확인이 필요한 약',
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub)),
              const SizedBox(height: 6),
              for (final d in flagged) _DrugRow(d),
            ],
            if (flagged.any((d) => d.isDanger)) ...[
              const SizedBox(height: 10),
              const KText('금기 약은 임의로 끊지 말고 약사·의사에게 먼저 확인하세요.',
                  style: TextStyle(fontSize: 12, color: AppColors.sub)),
            ],
          ],
        ),
      ),
    );
  }

  static String _dt(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.count,
    required this.icon,
    this.notApplicable = false,
  });

  final String label;
  final int count;
  final IconData icon;

  /// 복용자에게 해당 없는 항목 (예: 아이의 임부·수유부 금기)
  final bool notApplicable;

  @override
  Widget build(BuildContext context) {
    final hit = count > 0 && !notApplicable;
    final fg = notApplicable ? const Color(0xFF8A9691) : (hit ? _red : _green);
    final bg = notApplicable ? const Color(0xFFF1F4F3) : (hit ? _redBg : _greenBg);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: Center(
              child: notApplicable
                  ? Text('대상 아님',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13))
                  : hit
                      ? Text('$count개',
                          style: TextStyle(
                              color: fg, fontWeight: FontWeight.w800, fontSize: 20))
                      : Icon(Icons.check_rounded, color: fg, size: 26),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(ok ? Icons.check_circle : Icons.error,
          size: 20, color: ok ? _green : _red),
      const SizedBox(width: 8),
      Expanded(
        child: KText(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: ok ? AppColors.ink : _red)),
      ),
    ]);
  }
}

class _DrugRow extends StatelessWidget {
  const _DrugRow(this.d);

  final DrugSnap d;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (d.ageRule != null) _Chip('연령금기 ${d.ageRule}', danger: true),
      if (d.preg) const _Chip('임부금기', danger: true),
      if (d.mixWith.isNotEmpty) const _Chip('병용금기', danger: true),
      if (d.nursing) const _Chip('수유부 주의', danger: false),
      if (d.labelNote != null) const _Chip('설명서 사용연령', danger: false),
      if (d.needsPick) const _Chip('약 선택 필요', danger: false, gray: true),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: KText(d.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Wrap(
                alignment: WrapAlignment.end, spacing: 4, runSpacing: 4, children: chips),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.danger, this.gray = false});

  final String text;
  final bool danger;
  final bool gray;

  @override
  Widget build(BuildContext context) {
    final fg = gray ? const Color(0xFF455A64) : (danger ? _red : _orange);
    final bg = gray ? const Color(0xFFECEFF1) : (danger ? _redBg : _orangeBg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.primaryDark, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
