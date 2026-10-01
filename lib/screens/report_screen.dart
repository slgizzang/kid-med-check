import 'package:flutter/material.dart';

import '../logic/allergy.dart';
import '../logic/dur_api.dart';
import '../logic/models.dart';
import '../logic/report.dart';
import '../logic/storage.dart';
import '../ui/dashboard.dart' show kNoteBg, kNoteFg;
import '../ui/theme.dart';
import 'reaction_list_screen.dart';

/// 복용 리포트: 지난 기록을 모아 많이 먹은 약 계열, 반응 기록 패턴, 생활 관리 참고를 보여준다.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.person});

  final ChildProfile person;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  MedReport? _report;

  /// 알레르기 약물과 같은 성분이 들어 있던 기록 (약, 날짜, 알레르기)
  List<(String, DateTime, String)> _allergyFound = const [];
  int _done = 0, _total = 0;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final records =
        (await AppStorage.records()).where((r) => r.childId == widget.person.id).toList();
    final notes = await AppStorage.reactions(widget.person.id);

    // 지난 확인 결과에 저장된 분류·성분을 먼저 쓰고, 없는 약만 식약처 자료로 확인한다
    final meta = <String, DrugMeta>{};
    final names = <String, String>{};
    for (final r in records) {
      for (final d in r.last?.drugs ?? const []) {
        if (d.needsPick) continue;
        final k = drugKey(d.title);
        if (d.cls.isNotEmpty) meta[k] = DrugMeta(cls: d.cls, ingredient: d.ingredient);
      }
      for (final q in r.drugs) {
        final name = resolvedName(r, q);
        names.putIfAbsent(drugKey(name), () => name);
      }
    }
    final missing = names.entries.where((e) => !meta.containsKey(e.key)).toList();
    setState(() => _total = missing.length);
    if (missing.isNotEmpty) {
      final api = DurApi(await AppStorage.apiKey());
      // 한꺼번에 너무 많이 부르지 않도록 몇 개씩 나눠서
      for (var i = 0; i < missing.length; i += 6) {
        await Future.wait(missing.skip(i).take(6).map((e) async {
          try {
            final res = await api.resolve(e.value);
            final b = res.best;
            if (b != null && b.className.isNotEmpty) {
              meta[e.key] = DrugMeta(cls: b.className, ingredient: b.ingredient);
            }
          } catch (_) {}
          if (mounted) setState(() => _done++);
        }));
      }
    }
    if (!mounted) return;
    final found = <(String, DateTime, String)>[];
    if (widget.person.allergies.isNotEmpty) {
      for (final r in records) {
        for (final q in r.drugs) {
          final name = resolvedName(r, q);
          final m = meta[drugKey(name)];
          final hits = allergyHits(widget.person.allergies, name, m?.ingredient ?? '', m?.cls ?? '');
          if (hits.isNotEmpty) found.add((drugKey(name), r.createdAt, hits.first.allergy));
        }
      }
      found.sort((a, b) => b.$2.compareTo(a.$2));
    }
    setState(() {
      _allergyFound = found;
      _report = buildReport(records, notes, meta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: const KText('복용 리포트')),
      body: r == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                KText(_total == 0 ? '기록을 모으는 중…' : '약 분류 확인 중… $_done/$_total',
                    style: const TextStyle(color: AppColors.sub)),
              ]),
            )
          : r.records == 0
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: KText('아직 복용 기록이 없어요. 기록이 쌓이면 여기서 한눈에 볼 수 있어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.sub, height: 1.5)),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      16, 12, 16, 40 + MediaQuery.of(context).padding.bottom),
                  children: [
                    KText('${widget.person.name}님의 복용 리포트',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    if (r.from != null)
                      KText('${formatDate(r.from!)} ~ ${formatDate(r.to!)} 기록',
                          style: const TextStyle(color: AppColors.sub)),
                    const SizedBox(height: 14),
                    _Stats(r),
                    if (widget.person.allergies.isNotEmpty)
                      _Section(
                        title: '알레르기 약물',
                        sub: '복용자 정보에 입력한 알레르기예요',
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final a in widget.person.allergies)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFFDECEC),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Text(a,
                                    style: const TextStyle(
                                        color: Color(0xFFC62828), fontWeight: FontWeight.w700)),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          if (_allergyFound.isEmpty)
                            const KText('지난 복용 기록에는 같은 성분이 든 약이 없어요.',
                                style: TextStyle(color: AppColors.ink))
                          else ...[
                            KText('같은 성분이 든 약을 먹은 기록 ${_allergyFound.length}번',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, color: Color(0xFFC62828))),
                            for (final (d, at, a) in _allergyFound.take(5))
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: KText('${formatDate(at)} · $d ($a)',
                                    style: const TextStyle(color: AppColors.ink)),
                              ),
                          ],
                        ]),
                      ),
                    _Section(
                      title: '월별 복용 기록',
                      sub: '최근 12개월',
                      child: _MonthBars(r.monthly),
                    ),
                    _Section(
                      title: '많이 먹은 약 계열',
                      sub: '복용 기록 수 기준',
                      child: r.topClasses.isEmpty
                          ? const _Empty('약 분류를 확인한 기록이 아직 없어요.')
                          : _RankBars(r.topClasses),
                    ),
                    _Section(
                      title: '자주 먹은 약',
                      child: Column(children: [
                        for (final d in r.topDrugs) _DrugLine(d),
                      ]),
                    ),
                    _Section(
                      title: '복용 후 반응 요약',
                      sub: '적어둔 기록의 횟수·비율이에요. 원인을 판단한 것은 아니에요',
                      child: r.insights.isEmpty
                          ? const _Empty('적어둔 반응 기록이 없어요.')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final i in r.insights.take(3)) _InsightCard(i),
                                if (r.insights.length > 3)
                                  KText(
                                      '그 밖의 반응: ${r.insights.skip(3).map((i) => '${i.symptom} ${i.notes}번').join(', ')}',
                                      style: const TextStyle(fontSize: 13, color: AppColors.sub)),
                                const SizedBox(height: 6),
                                const KText(
                                  '자주 처방되는 약일수록 반응 기록과 겹치는 횟수도 많아질 수 있어요. '
                                  '반복되는 반응은 다음 진료 때 이 화면을 보여주며 의사·약사와 상의하세요.',
                                  style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                ReactionListScreen(person: widget.person))),
                                    icon: const Icon(Icons.list_alt, size: 18),
                                    label: const KText('반응 기록 전체 보기'),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    _Section(
                      title: '생활 관리·영양제 참고',
                      sub: '진단이나 처방이 아닌 일반 정보예요',
                      child: r.tips.isEmpty
                          ? const _Empty('아직 특별히 참고할 내용이 없어요.')
                          : Column(children: [
                              for (final t in r.tips) _TipCard(t),
                              const SizedBox(height: 4),
                              const KText(
                                '영양제·건강기능식품은 아이 나이와 먹는 약에 따라 맞지 않을 수 있어요. '
                                '먹이기 전에 꼭 약사·의사와 상의하세요.',
                                style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5),
                              ),
                            ]),
                    ),
                    if (r.unknownClass.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: KText(
                          '분류를 확인하지 못한 약 ${r.unknownClass.length}개는 계열 통계에서 빠졌어요.',
                          style: const TextStyle(fontSize: 12, color: AppColors.sub),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.sub, required this.child});
  final String title;
  final String? sub;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KText(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          if (sub != null)
            KText(sub!, style: const TextStyle(fontSize: 12, color: AppColors.sub)),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      KText(text, style: const TextStyle(color: AppColors.sub));
}

class _Stats extends StatelessWidget {
  const _Stats(this.r);
  final MedReport r;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value, String? sub) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 22, color: AppColors.ink, fontWeight: FontWeight.w800)),
              ),
              if (sub != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(sub,
                      maxLines: 1, style: const TextStyle(fontSize: 11, color: AppColors.sub)),
                ),
            ]),
          ),
        );
    return Row(children: [
      tile('복용 기록', '${r.records}', '처방 ${r.rxCount} · 일반 ${r.otcCount}'),
      const SizedBox(width: 8),
      tile('약 종류', '${r.drugKinds}', null),
      const SizedBox(width: 8),
      tile('반응 기록', '${r.reactionCount}', null),
    ]);
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars(this.months);
  final List<(DateTime, int)> months;

  @override
  Widget build(BuildContext context) {
    final maxV = months.fold<int>(1, (m, e) => e.$2 > m ? e.$2 : m);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (m, v) in months)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (v > 0)
                    Text('$v',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Container(
                    height: 70 * v / maxV + 2,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: v > 0 ? AppColors.primary : AppColors.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${m.month}월',
                      style: const TextStyle(fontSize: 10, color: AppColors.sub)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RankBars extends StatelessWidget {
  const _RankBars(this.items);
  final List<CountItem> items;

  @override
  Widget build(BuildContext context) {
    final maxV = items.first.count;
    return Column(children: [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: KText(it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
              Text('${it.count}번',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: it.count / maxV,
                minHeight: 8,
                backgroundColor: AppColors.line,
                color: AppColors.primary,
              ),
            ),
            if (it.examples.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: KText(it.examples.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.sub)),
              ),
          ]),
        ),
    ]);
  }
}

class _DrugLine extends StatelessWidget {
  const _DrugLine(this.d);
  final CountItem d;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KText(d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              if (d.last != null)
                KText('마지막 ${formatDate(d.last!)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.sub)),
            ]),
          ),
          Text('${d.count}번',
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        ]),
      );
}

class _TipCard extends StatelessWidget {
  const _TipCard(this.t);
  final CareTip t;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF8E6), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: KText(t.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A5A00))),
            ),
            Text(t.because, style: const TextStyle(fontSize: 11, color: Color(0xFF8A5A00))),
          ]),
          const SizedBox(height: 4),
          KText(t.body, style: const TextStyle(color: AppColors.ink, height: 1.5)),
        ]),
      );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard(this.i);
  final SymptomInsight i;

  static String _pct(int a, int b) => b == 0 ? '0%' : '${(a * 100 / b).round()}%';

  /// 라벨 · 막대 · 숫자 한 줄
  static Widget _bar(String label, int a, int b, {Color color = kNoteFg, String? right}) {
    final ratio = b == 0 ? 0.0 : a / b;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: KText(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600)),
          ),
          Text(right ?? '$b번 중 $a번',
              style: const TextStyle(fontSize: 12, color: AppColors.sub)),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            child: Text(_pct(a, b),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: Colors.white,
            color: color,
          ),
        ),
      ]),
    );
  }

  static Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(t,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kNoteFg)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(color: kNoteBg, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 증상 이름과 횟수
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: KText(i.symptom,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kNoteFg)),
          ),
          Text('${i.notes}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kNoteFg)),
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 4),
            child: Text('번 기록', style: TextStyle(fontSize: 13, color: kNoteFg)),
          ),
        ]),
        if (i.records > 0) _bar('전체 복용 중', i.records, i.totalRecords),
        if (i.dims.isNotEmpty) ...[
          _label('이 반응이 있을 때 가장 자주 함께 있던 것'),
          for (final d in i.dims) _DimRow(d, i.symptom),
        ],
        if (i.direct.isNotEmpty) ...[
          _label('약을 정해 적은 기록'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in i.direct)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Text('${d.$1} · ${d.$2}번',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: kNoteFg)),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// 약·성분·계열 하나: 반응 기록 중 몇 번 함께 있었는지 + 먹었을 때/안 먹었을 때 비율
class _DimRow extends StatelessWidget {
  const _DimRow(this.d, this.symptom);
  final SymptomDim d;
  final String symptom;

  static String _pct(int a, int b) => b == 0 ? '-' : '${(a * 100 / b).round()}%';

  Widget _mini(String label, int a, int b, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.sub)),
            ),
            Text(_pct(a, b),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: b == 0 ? 0 : a / b,
              minHeight: 6,
              backgroundColor: Colors.white,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text('$b번 중 $a번', style: const TextStyle(fontSize: 10, color: AppColors.sub)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: kNoteBg, borderRadius: BorderRadius.circular(6)),
            child: Text(d.kind,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kNoteFg)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KText(d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          Text('$symptom ${d.symTotal}번 중 ${d.inSym}번',
              style: const TextStyle(fontSize: 12, color: kNoteFg, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _mini('먹었을 때 $symptom', d.inSym, d.withTotal, const Color(0xFFC62828))),
          const SizedBox(width: 12),
          Expanded(
              child: _mini('안 먹었을 때 $symptom', d.withoutSym, d.withoutTotal,
                  const Color(0xFF8A9691))),
        ]),
      ]),
    );
  }
}
