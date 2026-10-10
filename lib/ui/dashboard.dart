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
const kNoteFg = Color(0xFF2B5B9E);
const kNoteBg = Color(0xFFEAF1FB);

/// 확인 결과 대시보드: 항목별 타일 + 확인이 필요한 약 목록 + 병용금기 조합
class ResultDashboard extends StatelessWidget {
  const ResultDashboard({
    super.key,
    required this.snap,
    required this.person,
    this.stale = false,
    this.showDate = false,
    this.ageMonths,
    this.recalled = const {},
    this.letters = const {},
  });

  /// 확인 기준 나이(개월). 없으면 스냅샷에 저장된 나이, 그것도 없으면 오늘 나이.
  final int? ageMonths;

  /// 식약처 회수 목록에 오른 약 / 주의 알림(안전성 서한)이 있었던 약 (기록의 약 이름)
  final Set<String> recalled;
  final Set<String> letters;

  bool _extra(DrugSnap d) => recalled.contains(d.query) || letters.contains(d.query);

  final ResultSnapshot snap;
  final ChildProfile person;

  /// 목록이 바뀌어 다시 확인해야 함
  final bool stale;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final age = ageMonths ?? snap.ageMonths ?? person.ageInMonths();
    // 사용 연령 확인은 아래 참고 타일로만 보여주고, 확인이 필요한 약 목록에서는 뺀다
    final flagged = snap.drugs
        .where((d) =>
            d.isDanger || d.nursing || d.needsPick || d.reaction != null || _extra(d))
        .toList();
    final labelN = snap.drugs.where((d) => d.labelNote != null && !d.isDanger).length;
    final pn = snap.pregnant || snap.nursing;
    final recallN = snap.drugs.where((d) => recalled.contains(d.query)).length;
    final letterN = snap.drugs.where((d) => letters.contains(d.query)).length;
    final pregHit = snap.pregnant ? snap.pregCount : 0;
    final nurseHit = snap.nursing ? snap.nursingCount : 0;
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
                child: KText('${person.name} · ${formatAge(age)}',
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
            // 항목별 타일 (메인 화면 전체 요약과 같은 구성)
            SafetyTiles(
              age: snap.ageCount,
              preg: pregHit + nurseHit,
              pregApplicable: pn,
              pregSoft: pregHit == 0,
              mix: snap.mixPairs.length,
              recall: recallN,
              letter: letterN,
              label: labelN,
            ),
            // 결과는 위 타일로 보여주므로 '…없음' 같은 문장은 쓰지 않는다. 문제가 있을 때만 무엇인지 짧게
            if (snap.allergyCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _Line(ok: false, text: '알레르기 약물과 같은 성분 ${snap.allergyCount}개'),
              ),
            if (snap.mixPairs.isNotEmpty) ...[
              const SizedBox(height: 12),
              const KText('함께 먹으면 안 되는 조합',
                  maxLines: 1,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub)),
              for (final p in snap.mixPairs)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: KText(p,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
                ),
            ],
            if (flagged.isNotEmpty) ...[
              const SizedBox(height: 14),
              const KText('확인이 필요한 약',
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub)),
              const SizedBox(height: 6),
              for (final d in flagged)
                _DrugRow(d,
                    recalled: recalled.contains(d.query), letter: letters.contains(d.query)),
            ],
            if (snap.reactionCount > 0) ...[
              const SizedBox(height: 10),
              const KText('지난 반응 기록이 있는 약은 처방받을 때 의사·약사에게 알려주세요.',
                  style: TextStyle(fontSize: 12, color: AppColors.sub)),
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

/// 안전 확인 항목 타일 5개: 연령금기 · 임부·수유부 금기 · 병용금기 / 회수된 약 · 식약처 주의 알림.
/// 안전 확인 결과 화면과 메인 화면 전체 요약이 같은 모양을 쓴다.
class SafetyTiles extends StatelessWidget {
  const SafetyTiles({
    super.key,
    required this.age,
    required this.preg,
    required this.mix,
    required this.recall,
    required this.letter,
    this.label = 0,
    this.pregApplicable = true,
    this.pregSoft = false,
  });

  final int age, preg, mix, recall, letter;

  /// 설명서상 사용 연령 전인 약 (금기 아님)
  final int label;

  /// 임신·수유 중이 아니면 '대상 아님'
  final bool pregApplicable;

  /// 수유부 주의만 있을 때 (금기가 아닌 주의라 주황)
  final bool pregSoft;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> tiles) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        );
    return Column(children: [
      row([
        _Tile(label: '연령금기', count: age, icon: Icons.child_care, info: _infoAge),
        _Tile(
            label: '임부·수유부 금기',
            count: preg,
            icon: Icons.pregnant_woman,
            notApplicable: !pregApplicable,
            soft: pregSoft,
            info: _infoPreg),
        _Tile(
            label: '병용금기', count: mix, unit: '쌍', icon: Icons.compare_arrows, info: _infoMix),
      ]),
      // 회수·주의 알림은 복용 금기가 아니라 참고 사항 — 한 단계 낮게(작고 옅게) 보여준다
      const SizedBox(height: 12),
      const Align(
        alignment: Alignment.centerLeft,
        child: KText('아래는 복용 금기가 아니에요. 복용할 때 참고하세요.',
            maxLines: 1, style: TextStyle(fontSize: 12, color: AppColors.sub)),
      ),
      const SizedBox(height: 6),
      row([
        _NoteTile(
            label: '회수된 약',
            count: recall,
            icon: Icons.assignment_return_outlined,
            info: _infoRecall),
        _NoteTile(
            label: '식약처 주의 알림',
            count: letter,
            icon: Icons.campaign_outlined,
            info: _infoLetter),
        _NoteTile(
            label: '사용 연령 확인',
            count: label,
            icon: Icons.menu_book_outlined,
            info: _infoLabel),
      ]),
      const SizedBox(height: 6),
      const Align(
        alignment: Alignment.centerLeft,
        child: KText('사용 연령이 실제 나이보다 높아도 의사 판단에 의해 처방될 수 있어요. (연령금기 ≠ 사용 연령)',
            flow: true, style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.45)),
      ),
    ]);
  }
}

const _infoAge = '이 나이에는 쓰면 안 된다고 식약처가 정한 약이에요 (DUR 특정연령대 금기). '
    '해당하는 약이 있으면 임의로 끊지 말고 처방한 의사나 약사에게 먼저 확인하세요.';
const _infoPreg = '임신 중에 먹으면 태아에게 해로울 수 있어 쓰지 않도록 정한 약(임부금기)과, '
    '수유 중에 주의가 필요한 약이에요. 임신·수유 중으로 등록한 복용자에게만 확인해요.';
const _infoMix = '함께 먹으면 부작용이 커지거나 약효가 달라져서 같이 쓰면 안 된다고 정한 약의 조합이에요 (DUR 병용금기).';
const _infoRecall = '품질 문제 등으로 제조사나 식약처가 회수한 약이에요. 회수는 보통 특정 제조번호만 해당하고 복용 금기는 아니에요. '
    '집에 남은 약이 있으면 약국에서 회수 대상인지 확인하세요.';
const _infoLetter = '새로 알려진 부작용 등을 식약처가 의사·약사에게 알린 안전성 서한이 있었던 약이에요. '
    '복용 금기는 아니고 참고 정보예요.';

const _infoLabel = '약 설명서에 적힌 사용 연령보다 어린 경우예요. 연령금기는 아니고, '
    '사용 연령 전이라도 의사 판단으로 처방될 수 있어요. 궁금하면 처방한 의사나 약사에게 물어보세요.';

/// 타일을 누르면 이 항목이 무엇인지 짧게 알려준다
void _showInfo(BuildContext context, String title, String body) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: KText(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      content: KText(body, flow: true, style: const TextStyle(fontSize: 15, height: 1.55)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const KText('확인'))],
    ),
  );
}

/// 참고 사항 타일 (회수·주의 알림): 금기 타일보다 작고 옅게, 한 줄로
class _NoteTile extends StatelessWidget {
  const _NoteTile(
      {required this.label, required this.count, required this.icon, required this.info});
  final String label;
  final int count;
  final IconData icon;
  final String info;

  @override
  Widget build(BuildContext context) {
    // 금기 타일과 같은 규칙: 없으면 초록, 있으면 빨강
    final hit = count > 0;
    final fg = hit ? _red : _green;
    return GestureDetector(
      onTap: () => _showInfo(context, label, info),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hit ? _redBg : _greenBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label,
                maxLines: 1,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ),
        const SizedBox(width: 4),
        Text(hit ? '$count건' : '없음',
            style: TextStyle(
                color: fg, fontWeight: hit ? FontWeight.w800 : FontWeight.w600, fontSize: 13)),
      ]),
    ));
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.count,
    required this.icon,
    this.unit = '개',
    this.notApplicable = false,
    this.soft = false,
    required this.info,
  });

  /// 눌렀을 때 보여줄 설명
  final String info;

  final String label;
  final int count;
  final IconData icon;
  final String unit;

  /// 금기가 아닌 주의 항목 (있으면 빨강 대신 주황)
  final bool soft;

  /// 복용자에게 해당 없는 항목 (예: 아이의 임부·수유부 금기)
  final bool notApplicable;

  @override
  Widget build(BuildContext context) {
    final hit = count > 0 && !notApplicable;
    // 모든 타일 같은 규칙: 해당 없음은 회색, 없으면 초록, 있으면 빨강
    final fg = notApplicable ? const Color(0xFF8A9691) : (hit ? _red : _green);
    final bg = notApplicable ? const Color(0xFFF1F4F3) : (hit ? _redBg : _greenBg);
    return GestureDetector(
      onTap: () => _showInfo(context, label, info),
      child: Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          // 위: 항목 이름 (한 줄) + 눌러서 설명을 볼 수 있다는 작은 표시
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    maxLines: 1,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(width: 2),
                Icon(Icons.info_outline_rounded, size: 13, color: fg.withAlpha(180)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          // 아래: 결과
          SizedBox(
            height: 30,
            child: Center(
              child: notApplicable
                  ? Text('대상 아님',
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14))
                  : hit
                      ? Text('$count$unit',
                          style: TextStyle(
                              color: fg, fontWeight: FontWeight.w800, fontSize: 22))
                      : Icon(Icons.check_rounded, color: fg, size: 28),
            ),
          ),
        ],
      ),
    ));
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(ok ? Icons.check_circle : Icons.error,
          size: 20, color: ok ? _green : _red),
      const SizedBox(width: 8),
      Expanded(
        child: KText(text,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: ok ? AppColors.ink : _red)),
      ),
    ]));
  }
}

class _DrugRow extends StatelessWidget {
  const _DrugRow(this.d, {this.recalled = false, this.letter = false});
  final bool recalled;
  final bool letter;

  final DrugSnap d;

  @override
  Widget build(BuildContext context) {
    // 아래 약별 카드의 상태 표시와 같은 이름을 쓴다
    final chips = <Widget>[
      if (d.allergy != null) const _Chip('알레르기 확인', danger: true),
      if (d.ageRule != null) const _Chip('연령금기 해당', danger: true),
      if (d.preg) const _Chip('임부금기', danger: true),
      if (d.mixWith.isNotEmpty) const _Chip('병용금기', danger: true),
      if (d.nursing) const _Chip('수유부 주의', danger: false),
      if (recalled) const _Chip('회수된 약', danger: true),
      if (letter) const _Chip('식약처 주의 알림', danger: false),
      if (d.needsPick) const _Chip('약 선택 필요', danger: false, gray: true),
      if (d.reaction != null) const _Chip('지난 반응 기록', danger: false, note: true),
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
  const _Chip(this.text, {required this.danger, this.gray = false, this.note = false});

  final String text;
  final bool danger;
  final bool gray;

  /// 보호자가 적은 반응 기록 (금기·주의와 구분되는 파란색)
  final bool note;

  @override
  Widget build(BuildContext context) {
    final fg = note
        ? kNoteFg
        : gray
            ? const Color(0xFF455A64)
            : (danger ? _red : _orange);
    final bg = note
        ? kNoteBg
        : gray
            ? const Color(0xFFECEFF1)
            : (danger ? _redBg : _orangeBg);
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
