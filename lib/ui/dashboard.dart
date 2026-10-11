import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/recall.dart' show recallRecordLabel;
import '../logic/snapshot.dart';
import 'theme.dart';

const _red = Color(0xFFC62828);
const _redBg = Color(0xFFFDECEC);
const _orange = Color(0xFFB45309);
const _orangeBg = Color(0xFFFFF4E8);
const _green = Color(0xFF1E7B3A);
const _greenBg = Color(0xFFEAF6EE);
const kNoteFg = Color(0xFF2B5B9E);
// 대시보드 타일 색: 바탕은 중립 회색, 결과 글자만 색으로 (화려한 면 색 대신)
const _tileBg = Color(0xFFF4F6F8);
const _alert = Color(0xFFE5484D);
const _alertBg = Color(0xFFFFF0F0);
const _okInk = Color(0xFF12805C);
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
        decoration: softCard(radius: 20),
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
    this.lists = const {},
    this.onOpen,
    this.pregApplicable = true,
    this.pregSoft = false,
  });

  final int age, preg, mix, recall, letter;

  /// 설명서상 사용 연령 전인 약 (금기 아님)
  final int label;

  /// 항목 이름 → 해당 기록 목록 (메인 화면 전체 요약에서만). 설명 창 아래에 보여주고 누르면 그 기록으로.
  final Map<String, List<(MedRecord, String)>> lists;
  final ValueChanged<MedRecord>? onOpen;

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
        _Tile(label: '연령금기',
            items: lists['연령금기'] ?? const [],
            onOpen: onOpen, count: age, icon: Icons.child_care, info: _infoAge),
        _Tile(
            label: '임부·수유부 금기',
            items: lists['임부·수유부 금기'] ?? const [],
            onOpen: onOpen,
            count: preg,
            icon: Icons.pregnant_woman,
            notApplicable: !pregApplicable,
            soft: pregSoft,
            info: _infoPreg),
        _Tile(
            label: '병용금기',
            items: lists['병용금기'] ?? const [],
            onOpen: onOpen, count: mix, unit: '쌍', icon: Icons.compare_arrows, info: _infoMix),
      ]),
      // 회수·주의 알림·사용 연령은 복용 금기가 아니라 참고 사항 — 한 묶음으로 작게
      const SizedBox(height: 12),
      const Align(
        alignment: Alignment.centerLeft,
        child: KText('참고 사항 · 복용 금기는 아니에요',
            maxLines: 1,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.sub)),
      ),
      const SizedBox(height: 6),
      row([
        _NoteTile(
                  label: '회수된 약',
                  items: lists['회수된 약'] ?? const [],
                  onOpen: onOpen,
                  count: recall,
                  icon: Icons.assignment_return_outlined,
                  info: _infoRecall),
        _NoteTile(
                  label: '식약처 주의 알림',
                  items: lists['식약처 주의 알림'] ?? const [],
                  onOpen: onOpen,
                  count: letter,
                  icon: Icons.campaign_outlined,
                  info: _infoLetter),
        _NoteTile(
                  label: '사용 연령 확인',
                  items: lists['사용 연령 확인'] ?? const [],
                  onOpen: onOpen,
                  count: label,
                  icon: Icons.menu_book_outlined,
                  info: _infoLabel),
      ]),
    ]);
  }
}

// 설명은 문장 하나씩 줄을 나눠 보여준다 (이어 쓰면 문장 중간에서 어색하게 끊긴다)
// 줄바꿈(\n)은 뜻이 끊기지 않는 곳에 미리 넣어 둔다 (자동으로 줄이 바뀌면 '사용 / 연령'처럼 어색하게 끊김)
const _infoAge = [
  '이 나이에 쓰면 안 된다고\n식약처가 정한 약이에요.',
  '해당하는 약이 있으면 임의로 끊지 말고\n의사나 약사에게 먼저 확인하세요.',
];
const _infoPreg = [
  '임신 중에 먹으면 태아에게\n해로울 수 있는 약(임부금기)이에요.',
  '수유 중에 주의가 필요한 약도\n함께 알려줘요.',
  '임신·수유 중으로 등록한\n복용자만 해당돼요.',
];
const _infoMix = [
  '함께 먹으면 부작용이 커지거나\n약효가 달라질 수 있는 약의 조합이에요.',
  '같이 처방됐다면\n의사나 약사에게 확인하세요.',
];
const _infoRecall = [
  '품질 문제 등으로\n제조사나 식약처가 회수한 약이에요.',
  '보통 특정 제조번호만 해당하고,\n복용 금기는 아니에요.',
  '남은 약이 있으면\n약국에서 회수 대상인지 확인하세요.',
];
const _infoLetter = [
  '새로 알려진 부작용 등을\n식약처가 의사·약사에게 알린 약이에요.',
  '복용 금기는 아니고\n참고 정보예요.',
];
const _infoLabel = [
  '약 설명서에 적힌\n사용 연령보다 어린 경우예요.',
  '연령금기는 아니고,\n의사 판단으로 처방될 수 있어요.',
  '궁금하면 의사나\n약사에게 물어보세요.',
];

/// 타일을 누르면 이 항목이 무엇인지 짧게 알려준다
void _showInfo(BuildContext context, String title, List<String> body,
    {List<(MedRecord, String)> items = const [], ValueChanged<MedRecord>? onOpen}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: KText(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < body.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final line in body[i].split('\n'))
                    KText(line, style: const TextStyle(fontSize: 15, height: 1.5)),
                ]),
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              KText('해당 기록 ${items.length}건',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 4),
              _InfoList(items: items, onOpen: onOpen == null
                  ? null
                  : (r) {
                      Navigator.pop(ctx);
                      onOpen(r);
                    }),
            ],
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const KText('닫기'))],
    ),
  );
}

/// 설명 창 안의 해당 기록 목록: 3건이 넘으면 접어 두고 펼쳐 본다. 누르면 그 기록의 안전 확인 결과로.
class _InfoList extends StatefulWidget {
  const _InfoList({required this.items, this.onOpen});
  final List<(MedRecord, String)> items;
  final ValueChanged<MedRecord>? onOpen;

  @override
  State<_InfoList> createState() => _InfoListState();
}

class _InfoListState extends State<_InfoList> {
  static const _folded = 3;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final more = items.length > _folded;
    final shown = !more || _open ? items : items.take(_folded).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (r, what) in shown)
        InkWell(
          onTap: widget.onOpen == null ? null : () => widget.onOpen!(r),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  KText(recallRecordLabel(r),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  KText(what,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.sub)),
                ]),
              ),
              if (widget.onOpen != null)
                const Icon(Icons.chevron_right, size: 20, color: AppColors.sub),
            ]),
          ),
        ),
      if (more)
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              KText(_open ? '접기' : '${items.length - _folded}건 더 보기',
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
              Icon(_open ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: AppColors.primaryDark),
            ]),
          ),
        ),
    ]);
  }
}


/// 대시보드 타일 공통 모양: 옅은 면 색 카드 (테두리 없이), 문제가 있으면 붉은 면.
/// 금기 타일(big)은 이름 두 줄 + 큰 결과, 참고 타일은 이름 한 줄 + 작은 결과로 낮게.
Widget _statTile(
  BuildContext context, {
  required Color accent,
  required Color bg,
  required IconData icon,
  required String label,
  required String value,
  required Color valueColor,
  required VoidCallback onTap,
  bool big = true,
  bool hit = false,
}) {
  final r = BorderRadius.circular(big ? 16 : 14);
  const labelStyle = TextStyle(
      color: Color(0xFF6B7684), fontWeight: FontWeight.w600, fontSize: 12.5, height: 1.25);
  return Material(
    color: bg,
    shape: RoundedRectangleBorder(
        borderRadius: r,
        side: hit ? BorderSide(color: accent.withAlpha(70)) : BorderSide.none),
    child: InkWell(
      borderRadius: r,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, big ? 11 : 9, 10, big ? 11 : 9),
        child: big
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 32,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(ka(label), maxLines: 2, style: labelStyle)),
                    const SizedBox(width: 2),
                    Icon(icon, size: 17, color: accent),
                  ]),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      maxLines: 1,
                      style: TextStyle(
                          color: valueColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 21,
                          letterSpacing: -0.4,
                          height: 1.2)),
                ),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(label, maxLines: 1, style: labelStyle.copyWith(fontSize: 12)),
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(icon, size: 15, color: accent),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(value,
                        maxLines: 1,
                        style: TextStyle(
                            color: valueColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                            letterSpacing: -0.3,
                            height: 1.2)),
                  ),
                ]),
              ]),
      ),
    ),
  );
}

const _okBg = Color(0xFFF3F6F5);
const _naBg = Color(0xFFF5F6F8);
const _okAccent = Color(0xFF12A37A);
const _naAccent = Color(0xFFB8C0C8);

/// 참고 사항 타일 (회수·주의 알림): 금기 타일보다 작고 옅게, 한 줄로
class _NoteTile extends StatelessWidget {
  const _NoteTile(
      {required this.label,
      required this.count,
      required this.icon,
      required this.info,
      this.items = const [],
      this.onOpen});
  final List<(MedRecord, String)> items;
  final ValueChanged<MedRecord>? onOpen;
  final String label;
  final int count;
  final IconData icon;
  final List<String> info;

  @override
  Widget build(BuildContext context) {
    final hit = count > 0;
    return _statTile(context,
        accent: hit ? _alert : _okAccent,
        bg: hit ? _alertBg : _okBg,
        hit: hit,
        icon: icon,
        label: label,
        value: hit ? '$count건' : '없음',
        valueColor: hit ? _alert : AppColors.ink,
        big: false,
        onTap: () => _showInfo(context, label, info, items: items, onOpen: onOpen));
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
    this.items = const [],
    this.onOpen,
  });

  /// 눌렀을 때 보여줄 설명
  final List<String> info;
  final List<(MedRecord, String)> items;
  final ValueChanged<MedRecord>? onOpen;

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
    return _statTile(context,
        accent: notApplicable ? _naAccent : (hit ? _alert : _okAccent),
        bg: notApplicable ? _naBg : (hit ? _alertBg : _okBg),
        hit: hit,
        icon: icon,
        label: label,
        value: notApplicable ? '대상 아님' : (hit ? '$count$unit' : '없음'),
        valueColor: notApplicable ? const Color(0xFF9AA3AD) : (hit ? _alert : AppColors.ink),
        onTap: () => _showInfo(context, label, info, items: items, onOpen: onOpen));
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
