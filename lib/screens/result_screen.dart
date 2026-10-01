import 'package:flutter/material.dart';

import '../logic/age_rule.dart';
import '../logic/allergy.dart';
import '../logic/drug_name_extractor.dart';
import '../logic/dur_api.dart';
import '../logic/dur_text.dart';
import '../logic/models.dart';
import '../logic/reaction.dart';
import '../logic/snapshot.dart';
import '../logic/storage.dart';
import '../ui/dashboard.dart';
import '../ui/reaction_sheet.dart';
import '../ui/theme.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen(
      {super.key,
      required this.child,
      required this.names,
      this.onReplace,
      this.onSnapshot,
      this.recordId = '',
      this.reuse,
      this.onChecks,
      this.asOf});

  /// 이 날짜 기준 나이로 확인 (처방 기록의 날짜). 없으면 오늘.
  final DateTime? asOf;

  /// 바뀐 것이 없을 때 지난 확인 결과를 그대로 보여준다 (다시 조회하지 않음)
  final List<DrugCheck>? reuse;

  /// 확인이 끝난 결과 (다음에 바뀐 게 없으면 재사용)
  final void Function(List<DrugCheck> checks)? onChecks;

  final ChildProfile child;
  final List<String> names;

  /// 반응 기록을 어느 처방 기록에 연결할지
  final String recordId;

  /// 비슷한 약을 골랐을 때 (입력한 이름, 고른 이름) — 처방 기록에 반영
  final void Function(String oldName, String newName)? onReplace;

  /// 확인이 끝날 때마다 결과 요약 — 처방 기록에 저장
  final void Function(ResultSnapshot snap)? onSnapshot;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final List<DrugCheck> _checks =
      widget.reuse ?? widget.names.map((n) => DrugCheck(n)).toList();
  /// 처방일 기준 나이 (지난 기록은 그때 나이로 확인)
  late final int _age = widget.child.ageInMonths(widget.asOf);
  bool get _adult => _age >= 19 * 12;

  /// 오늘이 아닌 지난 날짜 기준으로 확인하는지
  bool get _past {
    final d = widget.asOf;
    if (d == null) return false;
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
  }

  /// 이 복용자가 적어둔 복용 후 반응 기록
  List<ReactionNote> _notes = const [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
    if (widget.reuse == null) _run();
  }

  Future<void> _loadNotes() async {
    _notes = await AppStorage.reactions(widget.child.id);
    if (mounted) setState(() {});
  }

  List<(ReactionNote, ReactionMatch)> _notesFor(DrugCheck c) =>
      c.best == null
          ? const []
          : reactionsFor(_notes, c.title, c.ingredientText,
              recordId: widget.recordId, before: widget.asOf ?? DateTime.now());

  Future<void> _deleteReaction(ReactionNote n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const KText('이 반응 기록을 지울까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const KText('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const KText('지우기')),
        ],
      ),
    );
    if (ok != true) return;
    await AppStorage.deleteReaction(n.id);
    await _loadNotes();
    _report();
  }

  Future<void> _lookup(DurApi api, DrugCheck c) async {
    try {
      c.rows = const [];
      c.matchedQuery = null;
      c.best = null;
      c.similar = const [];
      c.info = null;
      c.infoLoading = true;
      c.labelFinding = null;

      // 1) 입력한 이름과 가장 비슷한 실제 제품을 찾는다 (오타 허용)
      final res = await api.resolve(c.query);
      c.best = res.best;
      c.similar = res.similar;
      if (mounted) setState(() {});

      // 2) 그 제품의 연령금기 정보. 확실한 제품을 못 찾았으면 추측하지 않고 물어본다.
      c.tabooNames = res.tabooNames;
      c.ambiguous = res.ambiguous;
      final best = c.best;
      if (best == null) {
        c.candidateTags = await _candidateTags(api, c.query, res);
        c.status = CheckStatus.notFound;
        c.infoLoading = false;
        if (mounted) setState(() {});
        return;
      }
      final rows = await api.searchAgeTaboo(best.searchName);
      c.rows = rows
          .where((r) =>
              DrugNameExtractor.toSearchName(ProductHit(fullName: r.itemName).displayName) ==
              best.searchName)
          .toList();
      c.matchedQuery = best.searchName;
      // 식약처 DUR 성분정보의 공식 연령 기준(AGE_BASE)을 우선 적용한다.
      await Future.wait(c.rows.where((r) => r.ingrCode.isNotEmpty).map((r) async {
        final base = await api.ingredientAgeBase(r.ingrCode);
        if (base.isNotEmpty) r.applyAgeBase(base);
      }));
      c.evaluate(_age);
    } catch (e) {
      c.status = CheckStatus.error;
      c.error = '$e';
    }
    if (mounted) setState(() {});

    // 3) 약 설명: 구분(전문/일반)·효능·성분을 항상 같은 형식으로.
    //    e약은요(효능)와 DUR 품목정보(구분·성분·분류)를 같은 제품끼리 합친다.
    final picked = c.best;
    if (picked == null) return;
    // 임부금기·병용금기는 약 이름만 있으면 되므로 설명을 모으는 동안 미리 조회
    final pregF = widget.child.pregnant ? api.pregnancyTaboo(picked) : null;
    final mixF = api.mixTaboo(picked);
    var best = picked;
    if (best.etcOtc.isEmpty || best.ingredient.isEmpty || best.className.isEmpty) {
      for (final h in await api.searchProducts(best.searchName)) {
        if (h.displayName == best.displayName) best = best.fillFrom(h);
      }
    }
    if (best.etcOtc.isEmpty || best.ingredient.isEmpty) {
      final permit = await api.permitInfo(best);
      if (permit != null) best = best.fillFrom(permit);
    }
    var className = best.className;
    if (className.isEmpty) {
      for (final r in c.rows) {
        if (r.className.isNotEmpty) {
          className = r.className;
          break;
        }
      }
    }
    // 성분도 품목정보에 없으면 연령금기 자료의 성분으로 채운다 (아래 성분 줄과 항상 일치하도록)
    var ingredient = best.ingredient;
    if (ingredient.isEmpty) {
      ingredient = {
        for (final r in c.rows)
          if (r.ingredient.isNotEmpty) r.ingredient
      }.join(', ');
    }
    var easy = best.easy;
    if (easy == null) {
      final found = await api.searchDrugInfo(best.displayName);
      if (found != null && found.itemName.startsWith(best.searchName) && found.efficacy.isNotEmpty) {
        easy = {
          'itemName': found.itemName,
          'efcyQesitm': found.efficacy,
          'useMethodQesitm': found.usage,
          'atpnQesitm': found.warnings,
        };
      }
    }
    // e약은요에 없는 약(대부분의 전문의약품)은 허가정보의 설명서 원문으로 효능·주의사항을 채운다
    Map<String, dynamic>? detail;
    if (easy == null) {
      detail = await api.permitDetail(best);
      if (detail != null) easy = detail;
    }
    if (ingredient.isEmpty && '${detail?['material'] ?? ''}'.isNotEmpty) {
      ingredient = '${detail!['material']}';
    }
    final etcOtc = best.etcOtc.isNotEmpty ? best.etcOtc : '${detail?['etcOtc'] ?? ''}';
    final fromEasy = easy != null ? DrugInfo.fromEasy(easy) : null;
    final DrugInfo info = DrugInfo(
      itemName: best.fullName,
      etcOtc: etcOtc,
      ingredient: ingredient,
      className: className,
      efficacy: fromEasy?.efficacy ?? '',
      usage: fromEasy?.usage ?? '',
      warnings: fromEasy?.warnings ?? '',
      source: detail != null
          ? '허가정보 · DUR 품목정보'
          : fromEasy != null
              ? 'e약은요 · DUR 품목정보'
              : 'DUR 품목정보',
    );
    c.info = info;
    c.ingredientText = [
      info.ingredient,
      for (final r in c.rows) r.ingredient,
    ].where((x) => x.isNotEmpty).join(', ');

    // 4) 임신·수유 중인 성인이면 임부금기·수유 주의, 그리고 병용금기 원자료
    final person = widget.child;
    // 복용자 알레르기 약물과 같은 성분·계열인지
    c.allergyHits = allergyHits(
        widget.child.allergies, best.fullName, c.ingredientText, className);
    if (pregF != null) c.pregRows = await pregF;
    if (person.nursing) c.nursingNote = _nursingSentence(info);
    c.mixRows = await mixF;

    c.infoLoading = false;
    if (c.status != CheckStatus.error) c.applyLabel(_age);
    if (mounted) setState(() {});
  }

  /// 후보 약마다 "이 복용자에게" 해당하는 주의만 표시한다.
  /// 아이: 나이에 실제로 걸리는 연령금기 / 임신 중: 임부금기
  Future<Map<String, List<String>>> _candidateTags(
      DurApi api, String query, Resolution res) async {
    final person = widget.child;
    final out = <String, List<String>>{};
    final preg = person.pregnant
        ? await api.pregnancyNames(DrugNameExtractor.toSearchName(query))
        : <String>{};
    for (final h in res.similar) {
      final tags = <String>[];
      if (!_adult) {
        final rows = res.tabooRows[h.displayName] ?? const <TabooRow>[];
        for (final r in rows) {
          if (r.ingrCode.isNotEmpty) {
            final base = await api.ingredientAgeBase(r.ingrCode);
            if (base.isNotEmpty) r.applyAgeBase(base);
          }
        }
        if (rows.any((r) => r.rule.appliesTo(_age) == true)) tags.add('연령금기');
      }
      if (preg.contains(h.displayName)) tags.add('임부금기');
      if (tags.isNotEmpty) out[h.displayName] = tags;
    }
    return out;
  }

  /// 설명서에서 수유부에 해당하는 내용만 짧게
  static String? _nursingSentence(DrugInfo info) =>
      nursingSummary('${info.warnings} ${info.usage} ${info.efficacy}');

  /// 같은 기록 안의 약끼리 DUR 병용금기에 걸리는 조합을 찾는다.
  void _computeInteractions() {
    for (final c in _checks) {
      c.interactions = [];
    }
    String norm(String s) => s.replaceAll(RegExp(r'\s'), '');
    String? match(DrugCheck a, DrugCheck b) {
      final bName = b.best!.displayName;
      final bIngr = norm(b.ingredientText);
      for (final r in a.mixRows) {
        final byName = r.partnerItem.isNotEmpty &&
            ProductHit(fullName: r.partnerItem).displayName == bName;
        final pi = norm(r.partnerIngr);
        final byIngr = pi.length >= 3 &&
            bIngr.isNotEmpty &&
            (bIngr.contains(pi) || pi.contains(bIngr));
        if (byName || byIngr) {
          return r.reason.isEmpty ? '함께 쓰면 위험할 수 있는 조합이에요.' : r.reason;
        }
      }
      return null;
    }

    // 성분 단위 병용금기 표로도 대조 (제품 목록이 길어 잘린 경우 대비)
    String? byTable(DrugCheck a, DrugCheck b) {
      final ai = norm(a.ingredientText), bi = norm(b.ingredientText);
      if (ai.isEmpty || bi.isEmpty) return null;
      for (final p in _mixTable) {
        final pa = norm(p.a), pb = norm(p.b);
        if (pa.length < 2 || pb.length < 2) continue;
        if ((ai.contains(pa) && bi.contains(pb)) || (ai.contains(pb) && bi.contains(pa))) {
          return p.reason.isEmpty ? '함께 쓰면 위험할 수 있는 조합이에요.' : p.reason;
        }
      }
      return null;
    }

    final ok = _checks.where((c) => c.best != null).toList();
    for (var i = 0; i < ok.length; i++) {
      for (var j = i + 1; j < ok.length; j++) {
        final a = ok[i], b = ok[j];
        final reason = match(a, b) ?? match(b, a) ?? byTable(a, b);
        if (reason != null) {
          a.interactions.add(Interaction(b.title, reason));
          b.interactions.add(Interaction(a.title, reason));
        }
      }
    }
    if (mounted) setState(() {});
  }

  /// 지금 결과를 요약 스냅샷으로 (대시보드·기록 저장용)
  ResultSnapshot _snapshot() {
    final pairs = <String>{};
    for (final c in _checks) {
      for (final x in c.interactions) {
        final pair = [c.title, x.other]..sort();
        pairs.add(pair.join(' + '));
      }
    }
    return ResultSnapshot(
      at: DateTime.now(),
      drugs: [
        for (final c in _checks)
          DrugSnap(
            query: c.query,
            title: c.title,
            ageRule: c.status == CheckStatus.danger ? _ruleText(c.dangerRows(_age)) : null,
            labelNote: c.status == CheckStatus.labelCaution ? c.labelFinding?.evidence : null,
            preg: c.hasPreg,
            nursing: c.nursingNote != null,
            mixWith: c.interactions.map((x) => x.other).toList(),
            needsPick: c.status == CheckStatus.notFound,
            ingredient: c.best != null ? c.ingredientText : '',
            cls: c.info?.className ?? '',
            allergy: c.hasAllergy ? c.allergyHits.first.allergy : null,
            reaction: _notesFor(c).isEmpty ? null : _notesFor(c).first.$1.summary,
          ),
      ],
      mixPairs: pairs.toList(),
      pregnant: widget.child.pregnant,
      nursing: widget.child.nursing,
      ageMonths: _age,
      allergies: widget.child.allergies,
    );
  }

  void _report() {
    widget.onSnapshot?.call(_snapshot());
    final done = _checks.every((c) => c.status != CheckStatus.loading && !c.infoLoading);
    if (done && !_checks.any((c) => c.status == CheckStatus.error)) {
      widget.onChecks?.call(_checks);
    }
  }

  DurApi? _api;
  List<MixPair> _mixTable = const [];

  /// "혹시 이 약인가요?"에서 고르면 그 약으로 카드를 다시 만들고 기록에도 반영한다.
  Future<void> _pick(DrugCheck old, String name) async {
    final i = _checks.indexOf(old);
    if (i < 0) return;
    final n = DrugCheck(name);
    setState(() => _checks[i] = n);
    widget.onReplace?.call(old.query, name);
    await _lookup(_api ?? DurApi(await AppStorage.apiKey()), n);
    _computeInteractions();
    _report();
  }

  Future<void> _run() async {
    final api = DurApi(await AppStorage.apiKey());
    _api = api;
    await Future.wait([
      ..._checks.map((c) => _lookup(api, c)),
      if (_checks.length > 1)
        api.ingredientMixTable().then((t) => _mixTable = t),
    ]);
    _computeInteractions();
    _report();
  }

  Future<void> _retry(DrugCheck c) async {
    setState(() {
      c.status = CheckStatus.loading;
      c.error = null;
    });
    await _lookup(DurApi(await AppStorage.apiKey()), c);
    _computeInteractions();
    _report();
  }

  @override
  Widget build(BuildContext context) {
    final done = _checks
        .every((c) => c.status != CheckStatus.loading && !c.infoLoading);
    final order = [
      CheckStatus.danger,
      CheckStatus.labelCaution,
      CheckStatus.notFound,
      CheckStatus.unknown,
      CheckStatus.error,
      CheckStatus.loading,
      CheckStatus.listedOk,
      CheckStatus.notListed,
    ];
    int rank(DrugCheck c) => c.isDanger ? -1 : order.indexOf(c.status);
    final sorted = [..._checks]..sort((a, b) => rank(a).compareTo(rank(b)));

    return Scaffold(
      appBar: AppBar(title: const KText('안전 확인 결과')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 40 + MediaQuery.of(context).padding.bottom),
        children: [
          const KText('종합 결과',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
          const SizedBox(height: 8),
          if (!done)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(width: 12),
                Expanded(
                  child: KText('${widget.child.name} (${formatAge(_age)}) 기준으로 확인 중…',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            )
          else
            ResultDashboard(snap: _snapshot(), person: widget.child, ageMonths: _age),
          const SizedBox(height: 28),
          KText('약별 결과 · ${_checks.length}개',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
          const SizedBox(height: 8),
          for (final c in sorted)
            _CheckCard(
                check: c,
                age: _age,
                adult: _adult,
                pregnant: widget.child.pregnant,
                past: _past,
                notes: _notesFor(c),
                onDeleteReaction: _deleteReaction,
                onRetry: () => _retry(c),
                onPick: (name) => _pick(c, name)),
          const SizedBox(height: 16),
          const _Sources(),
        ],
      ),
    );
  }
}

/// 카드 안의 경고 블록 (병용금기·임부금기·수유 주의)
class _Alert extends StatelessWidget {
  const _Alert({required this.title, required this.body, required this.danger});

  final String title;
  final String body;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? const Color(0xFFB71C1C) : const Color(0xFF9A3412);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFDECEC) : const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KText(title, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          KText(body, style: TextStyle(color: fg, height: 1.45)),
        ],
      ),
    );
  }
}

String _ruleText(List<TabooRow> rows) =>
    AgeRule.summarize([for (final r in rows) ...r.rule.conditions]);

class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.check,
    required this.age,
    required this.adult,
    this.pregnant = false,
    this.past = false,
    required this.onRetry,
    required this.onPick,
    this.notes = const [],
    this.onAddReaction,
    this.onDeleteReaction,
  });

  final List<(ReactionNote, ReactionMatch)> notes;
  final VoidCallback? onAddReaction;
  final ValueChanged<ReactionNote>? onDeleteReaction;

  final DrugCheck check;
  final int age;
  final bool adult;
  final bool pregnant;

  /// 지난 처방 기록을 그때 나이로 확인하는 중
  final bool past;
  final VoidCallback onRetry;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var (Color bg, Color fg, IconData icon, String label) = switch (check.status) {
      CheckStatus.loading => (
          const Color(0xFFF1F3F4),
          Colors.black54,
          Icons.hourglass_empty,
          '조회 중'
        ),
      CheckStatus.danger => (
          const Color(0xFFFDE7E7),
          const Color(0xFFC62828),
          Icons.dangerous_outlined,
          '연령금기 해당'
        ),
      CheckStatus.labelCaution => (
          const Color(0xFFFFE9D6),
          const Color(0xFFB45309),
          Icons.warning_amber_rounded,
          '사용 연령 확인'
        ),
      CheckStatus.notFound => (
          const Color(0xFFECEFF1),
          const Color(0xFF455A64),
          check.ambiguous ? Icons.touch_app_outlined : Icons.search_off,
          '약 선택 필요'
        ),
      CheckStatus.unknown => (
          const Color(0xFFFFF4D6),
          const Color(0xFF8A6100),
          Icons.help_outline,
          '내용 확인 필요'
        ),
      CheckStatus.listedOk => (
          const Color(0xFFE6F4EA),
          const Color(0xFF1E7B3A),
          Icons.check_circle_outline,
          '연령금기 없음'
        ),
      CheckStatus.notListed => (
          const Color(0xFFE6F4EA),
          const Color(0xFF1E7B3A),
          Icons.check_circle_outline,
          '연령금기 없음'
        ),
      CheckStatus.error => (
          const Color(0xFFF1F3F4),
          Colors.black87,
          Icons.cloud_off_outlined,
          '조회 실패'
        ),
    };

    final ageIrrelevant = adult && check.status == CheckStatus.unknown;
    final pregnantNoTaboo = pregnant && !check.hasPreg;
    if (ageIrrelevant) {
      bg = const Color(0xFFE6F4EA);
      fg = const Color(0xFF1E7B3A);
      icon = Icons.check_circle_outline;
      // 성인은 연령금기 대상이 아니므로 실제로 확인한 항목 이름으로
      label = pregnantNoTaboo ? '임부금기 없음' : '병용금기 없음';
    }
    if (adult &&
        (check.status == CheckStatus.listedOk || check.status == CheckStatus.notListed)) {
      label = pregnantNoTaboo ? '임부금기 없음' : '병용금기 없음';
    }
    if (check.nursingNote != null && !check.isDanger) {
      bg = const Color(0xFFFFE9D6);
      fg = const Color(0xFFB45309);
      icon = Icons.warning_amber_rounded;
      label = '수유부 주의';
    }
    if (check.hasAllergy) {
      bg = const Color(0xFFFDE7E7);
      fg = const Color(0xFFC62828);
      icon = Icons.dangerous_outlined;
      label = '알레르기 확인';
    }
    if (check.hasMix || check.hasPreg) {
      bg = const Color(0xFFFDE7E7);
      fg = const Color(0xFFC62828);
      icon = Icons.dangerous_outlined;
      label = check.hasMix ? '병용금기' : '임부금기';
    }
    // 사용자에게 해당하는 연령금기만 보여준다 (해당 없는 건 설명하지 않음)
    final groups = _IngredientGroup.from(check.rows, age)
        .where((g) => g.applies == true || (g.applies == null && !adult))
        .toList();
    final verdict = ageIrrelevant ? null : _verdict(check, age, groups, past: past);

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KText(check.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (check.best != null &&
                        check.best!.searchName !=
                            DrugNameExtractor.toSearchName(check.query))
                      KText('입력한 이름: ${check.query}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.black54)),
                    if (check.best != null &&
                        (check.best!.company.isNotEmpty || check.best!.etcOtc.isNotEmpty))
                      KText(
                        [check.best!.company, check.best!.etcOtc]
                            .where((x) => x.isNotEmpty)
                            .join(' · '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.black54),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: KText(label,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ]),
            if (verdict != null) ...[
              const SizedBox(height: 10),
              KText(verdict,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w600, height: 1.4)),
            ],
            for (final x in check.interactions)
              _Alert(
                  title: '병용금기 · ${x.other}',
                  body: '${x.other}와(과) 함께 먹으면 안 되는 조합이에요. ${friendlyTaboo(x.reason)}',
                  danger: true),
            for (final h in check.allergyHits)
              _Alert(
                  title: '알레르기 확인 · ${h.allergy}',
                  body: '입력한 알레르기 약물(${h.allergy})과 같은 성분(${h.matched})이 들어 있어요. '
                      '먹이기 전에 알레르기가 있다고 약사·의사에게 꼭 알려주세요.',
                  danger: true),
            if (check.hasPreg)
              _Alert(
                  title: '임부금기',
                  body: check.pregRows.first.content.isEmpty
                      ? '임신 중에는 쓰지 않도록 지정된 약이에요.'
                      : friendlyTaboo(check.pregRows.first.content),
                  danger: true),
            if (check.nursingNote != null)
              _Alert(title: '수유부 주의', body: check.nursingNote!, danger: false),
            ReactionNotesView(items: notes, onDelete: onDeleteReaction),
            if (check.status == CheckStatus.error) ...[
              const SizedBox(height: 8),
              KText(check.error ?? ''),
              TextButton(onPressed: onRetry, child: const KText('다시 시도')),
            ],
            _InfoView(check: check),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (groups.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: KText(
                    '성분이 다른 약 ${groups.length}종이 함께 나왔어요. 처방받은 약의 성분 줄만 보세요.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final g in groups) _IngredientView(group: g),
            ],
            if (check.status == CheckStatus.notFound && check.similar.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: KText('비슷한 이름의 약도 없어요. 처방받은 약 이름을 다시 확인해 입력해주세요.',
                    style: theme.textTheme.bodySmall),
              ),
            // 약이 확정되면 후보는 보여주지 않는다 (고를 필요가 있을 때만)
            if (check.best == null && check.similar.isNotEmpty) ...[
              const SizedBox(height: 12),
              KText(check.ambiguous ? '처방받은 약을 골라주세요' : '혹시 찾으시는 약이 이것인가요?',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final h in check.similar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: const Color(0xFFF4F7F6),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onPick(h.displayName),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                KText(h.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (h.ingredient.isNotEmpty || h.company.isNotEmpty)
                                  KText(
                                    [h.ingredient, h.company]
                                        .where((x) => x.isNotEmpty)
                                        .join(' · '),
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.black54),
                                  ),
                              ],
                            ),
                          ),
                          for (final tag in check.candidateTags[h.displayName] ?? const <String>[])
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDE7E7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(tag,
                                  style: const TextStyle(
                                      color: Color(0xFFC62828),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ),
                          const Icon(Icons.chevron_right, color: Colors.black38),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
            if (check.best != null && !check.infoLoading && onAddReaction != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAddReaction,
                  icon: const Icon(Icons.edit_note, size: 20),
                  label: const KText('복용 후 반응 기록'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 카드 맨 위에 보여줄 한 줄 결론
  static String? _verdict(DrugCheck c, int age, List<_IngredientGroup> groups,
      {bool past = false}) {
    final a = formatAge(age);
    switch (c.status) {
      case CheckStatus.danger:
        final src = AgeRule.summarize([
          for (final g in groups.where((g) => g.applies == true)) ...g.conds
        ]);
        return past
            ? '당시 $a 기준 연령금기에 해당했어요 (연령금기 기준: $src)'
            : '$a 기준 연령금기에 해당해요 (연령금기 기준: $src)';
      case CheckStatus.labelCaution:
        final f = c.labelFinding;
        if (f == null) return null;
        // 설명서상 사용 연령보다 어리면 금지 문구든 권장 연령이든 항상 같은 안내를 붙인다
        const note = '다만 DUR 연령금기약은 아니에요. 사용 연령보다 어려도 의사가 판단해 처방할 수 있어요. '
            '걱정되면 약사에게 용량을 한 번 더 확인하세요.';
        return f.prohibited
            ? '설명서에 "${f.evidence}"라고 되어 있고, ${past ? '당시 나이($a)가 해당했어요' : '현재 나이($a)가 해당해요'}. $note'
            : '설명서에는 "${f.evidence}"에게 쓰는 약으로 되어 있어요. ${past ? '당시 나이($a)는 이보다 어렸어요' : '현재 나이($a)는 이보다 어려요'}. $note';
      case CheckStatus.unknown:
        return '연령금기 목록에 있지만 나이 기준이 적혀 있지 않아요. 약사에게 몇 살부터 먹을 수 있는지 확인하세요.';
      case CheckStatus.listedOk:
        return null;
      case CheckStatus.notListed:
        return null;
      case CheckStatus.notFound:
        return c.ambiguous
            ? '"${c.query}"(으)로 찾은 약이 여러 개예요. 처방받은 약이 어떤 건지 아래에서 골라주세요.'
            : '"${c.query}"(와)과 정확히 맞는 약을 찾지 못했어요. 아래에서 처방받은 약을 골라주세요.';
      case CheckStatus.loading:
      case CheckStatus.error:
        return null;
    }
  }
}

/// 같은 성분끼리 묶은 금기 정보
class _IngredientGroup {
  _IngredientGroup(this.name);

  final String name;
  final List<TabooRow> rows = [];
  bool? applies;
  final List<AgeCondition> conds = [];

  /// 화면에 보여줄 연령금기 기준 한 문구 (예: "12세 이하")
  String get label => AgeRule.summarize(conds);
  final Set<String> reasons = {};
  bool assumed = false;
  String ageBase = '';

  static List<_IngredientGroup> from(List<TabooRow> rows, int age) {
    final map = <String, _IngredientGroup>{};
    for (final r in rows) {
      final key = r.ingredient.isNotEmpty ? r.ingredient : r.itemName;
      final g = map.putIfAbsent(key, () => _IngredientGroup(key));
      g.rows.add(r);
    }
    for (final g in map.values) {
      final results = g.rows.map((r) => r.rule.appliesTo(age)).toList();
      g.applies = results.contains(true)
          ? true
          : results.contains(null)
              ? null
              : false;
      for (final r in g.rows) {
        for (final c in r.rule.conditions) {
          g.conds.add(c);
        }
        final reason = r.content.replaceAll(RegExp(r'^[\s_\-]+|[\s_\-]+$'), '');
        if (reason.length > 1) g.reasons.add(friendlyTaboo(reason));
        if (r.ageBase.isNotEmpty) g.ageBase = r.ageBase;
      }
      // 공식 기준이 하나라도 있으면 "추정" 표시는 하지 않는다
      g.assumed = g.conds.isNotEmpty && g.conds.every((c) => c.assumed);
    }
    final list = map.values.toList();
    int rank(_IngredientGroup g) => g.applies == true ? 0 : g.applies == null ? 1 : 2;
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }
}

class _IngredientView extends StatelessWidget {
  const _IngredientView({required this.group});

  final _IngredientGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = group;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KText('성분: ${g.name}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (g.label.isNotEmpty) ...[
            const SizedBox(height: 4),
            KText('연령금기 기준: ${g.label}',
                style: theme.textTheme.bodyMedium),
          ],
          if (g.ageBase.isNotEmpty)
            KText('(나이 기준 출처: 식약처 DUR 성분정보)',
                style: theme.textTheme.bodySmall),
          if (g.reasons.isNotEmpty) ...[
            const SizedBox(height: 4),
            KText('사유: ${g.reasons.first}',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          ],
          if (g.applies == true && g.assumed) ...[
            const SizedBox(height: 6),
            KText(
              '판단 사유: 정확한 연령이 적혀 있지 않지만 "소아" 등으로 되어 있어 금기 약품으로 보았어요.',
              style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// 어떤 약인지 간단한 설명
class _InfoView extends StatelessWidget {
  const _InfoView({required this.check});

  final DrugCheck check;

  static String _firstSentences(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    final cut = text.substring(0, maxLen);
    final end = cut.lastIndexOf('.');
    return end > 30 ? cut.substring(0, end + 1) : '$cut…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = check.info;
    if (check.status == CheckStatus.notFound) return const SizedBox.shrink();
    if (info == null) {
      if (check.infoLoading && check.status != CheckStatus.error) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: KText('약 설명 찾는 중…', style: theme.textTheme.bodySmall),
        );
      }
      if (!check.infoLoading) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: KText('이 이름으로는 약 설명을 찾지 못했어요.',
              style: theme.textTheme.bodySmall),
        );
      }
      return const SizedBox.shrink();
    }

    final ingredient = info.ingredient.isNotEmpty
        ? info.ingredient
        : (check.best?.ingredient ?? '');
    final etc = info.etcOtc.contains('전문')
        ? '전문의약품'
        : info.etcOtc.contains('일반')
            ? '일반의약품'
            : info.etcOtc;
    // 효능은 모두 짧은 명사 나열형으로 (예: "기침, 가래" / "진해거담제")
    final String efficacy;
    final phrase = efficacyPhrase(info.efficacy);
    if (phrase.isNotEmpty) {
      efficacy = phrase;
    } else if (info.className.isNotEmpty) {
      efficacy = info.className;
    } else {
      efficacy = '정보 없음';
    }

    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: KText(k,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.black54, height: 1.5)),
              ),
              Expanded(
                child: KText(v,
                    style: TextStyle(
                        height: 1.45,
                        fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row('구분', etc.isEmpty ? '정보 없음' : etc, bold: true),
          row('효능', efficacy),
          row('성분', ingredient.isEmpty ? '정보 없음' : ingredient),
        ],
      ),
    );
  }
}

/// 화면 맨 아래 출처 (항목마다 한 줄씩, 어색하게 끊기지 않도록)
class _Sources extends StatelessWidget {
  const _Sources();

  static const _items = [
    ('의약품안전사용서비스(DUR) 품목·성분 정보', '연령금기, 임부금기, 병용금기'),
    ('의약품개요정보(e약은요)', '효능, 설명서의 사용 연령, 수유부 주의'),
    ('의약품 제품 허가정보', '성분, 전문·일반 구분, 설명서(효능·주의사항)'),
  ];

  static Widget _fit(String t, TextStyle style) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(t, maxLines: 1, softWrap: false, style: style),
      );

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KText('출처: 식품의약품안전처 공공데이터',
            style: TextStyle(fontSize: 12, color: AppColors.sub, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        // 출처 이름 한 줄, 쓰는 항목은 다음 줄에 (각각 한 줄에 맞춤)
        for (final (name, use) in _items) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _fit('· $name', small),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: _fit(': $use', small),
          ),
        ],
        const SizedBox(height: 8),
        const KText('이 앱은 참고용이며 의학적 판단을 대신하지 않아요.', style: small),
      ],
    );
  }
}
