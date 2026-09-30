import 'package:flutter/material.dart';

import '../logic/age_rule.dart';
import '../logic/drug_name_extractor.dart';
import '../logic/dur_api.dart';
import '../logic/models.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen(
      {super.key, required this.child, required this.names, this.onReplace});

  final ChildProfile child;
  final List<String> names;

  /// 비슷한 약을 골랐을 때 (입력한 이름, 고른 이름) — 처방 기록에 반영
  final void Function(String oldName, String newName)? onReplace;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final List<DrugCheck> _checks =
      widget.names.map((n) => DrugCheck(n)).toList();
  late final int _age = widget.child.ageInMonths();

  @override
  void initState() {
    super.initState();
    _run();
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
    var best = picked;
    if (best.etcOtc.isEmpty || best.ingredient.isEmpty || best.className.isEmpty) {
      for (final h in await api.searchProducts(best.searchName)) {
        if (h.displayName == best.displayName) best = best.fillFrom(h);
      }
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
    final fromEasy = easy != null ? DrugInfo.fromEasy(easy) : null;
    final DrugInfo info = DrugInfo(
      itemName: best.fullName,
      etcOtc: best.etcOtc,
      ingredient: best.ingredient,
      className: className,
      efficacy: fromEasy?.efficacy ?? '',
      usage: fromEasy?.usage ?? '',
      warnings: fromEasy?.warnings ?? '',
      source: fromEasy != null ? 'e약은요 · DUR 품목정보' : 'DUR 품목정보',
    );
    c.info = info;
    c.infoLoading = false;
    if (c.status != CheckStatus.error) c.applyLabel(_age);
    if (mounted) setState(() {});
  }

  DurApi? _api;

  /// "혹시 이 약인가요?"에서 고르면 그 약으로 카드를 다시 만들고 기록에도 반영한다.
  Future<void> _pick(DrugCheck old, String name) async {
    final i = _checks.indexOf(old);
    if (i < 0) return;
    final n = DrugCheck(name);
    setState(() => _checks[i] = n);
    widget.onReplace?.call(old.query, name);
    await _lookup(_api ?? DurApi(await AppStorage.apiKey()), n);
  }

  Future<void> _run() async {
    final api = DurApi(await AppStorage.apiKey());
    _api = api;
    await Future.wait(_checks.map((c) => _lookup(api, c)));
  }

  Future<void> _retry(DrugCheck c) async {
    setState(() {
      c.status = CheckStatus.loading;
      c.error = null;
    });
    await _lookup(DurApi(await AppStorage.apiKey()), c);
  }

  @override
  Widget build(BuildContext context) {
    final done = _checks
        .every((c) => c.status != CheckStatus.loading && !c.infoLoading);
    final dangers = _checks.where((c) => c.status == CheckStatus.danger).toList();
    final cautions =
        _checks.where((c) => c.status == CheckStatus.labelCaution).toList();
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
    final sorted = [..._checks]
      ..sort((a, b) => order.indexOf(a.status).compareTo(order.indexOf(b.status)));

    return Scaffold(
      appBar: AppBar(title: const Text('확인 결과')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 40 + MediaQuery.of(context).padding.bottom),
        children: [
          const Text('종합 결과',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
          const SizedBox(height: 8),
          _Summary(
              child: widget.child,
              done: done,
              dangers: dangers,
              cautions: cautions,
              pending: _checks.where((c) => c.status == CheckStatus.notFound).length,
              age: _age),
          const SizedBox(height: 28),
          Text('약별 결과 · ${_checks.length}개',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
          const SizedBox(height: 8),
          for (final c in sorted)
            _CheckCard(
                check: c,
                age: _age,
                onRetry: () => _retry(c),
                onPick: (name) => _pick(c, name)),
          const SizedBox(height: 16),
          Text(
            '출처: 식품의약품안전처 의약품안전사용서비스(DUR) 품목정보 - 특정연령대금기. '
            '"목록에 없음"은 이 이름으로 연령금기 품목이 검색되지 않았다는 뜻이며, '
            '약 이름이 정확하지 않으면 결과가 나오지 않을 수 있어요. '
            '이 앱은 참고용이며 의학적 판단을 대신하지 않아요.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary(
      {required this.child,
      required this.done,
      required this.dangers,
      required this.cautions,
      required this.pending,
      required this.age});

  final ChildProfile child;
  final bool done;
  final List<DrugCheck> dangers;
  final List<DrugCheck> cautions;

  /// 약을 골라야 해서 아직 판정 못 한 개수
  final int pending;
  final int age;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!done) {
      return _Banner(
        color: const Color(0xFFEFF3F2),
        child: ListTile(
          leading: const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          title: Text('${child.name} (${child.ageLabel}) 기준으로 확인 중…'),
        ),
      );
    }
    final pendingNote = pending == 0
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('※ 아직 약을 고르지 않은 항목이 $pending개 있어요. 아래 카드에서 골라야 확인돼요.',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          );
    if (dangers.isEmpty && cautions.isEmpty && pending > 0) {
      return _Banner(
        color: const Color(0xFFECEFF1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.touch_app_outlined, color: Color(0xFF455A64), size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '정확한 약을 골라야 하는 항목이 $pending개 있어요.\n아래 카드에서 처방받은 약을 골라주세요.',
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      );
    }
    if (dangers.isEmpty && cautions.isEmpty) {
      return _Banner(
        color: const Color(0xFFE6F4EA),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${child.name}(${child.ageLabel}) 나이에 연령금기이거나 '
            '설명서상 사용 연령보다 어린 약은 찾지 못했어요.\n'
            '노란색·회색 항목이 있다면 내용을 한 번 더 확인해주세요.',
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }
    if (dangers.isEmpty) {
      return _Banner(
        color: const Color(0xFFFFE9D6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFB45309), size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '설명서상 사용 연령보다 어린 약이 ${cautions.length}개 있어요',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF9A3412),
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
              if (pendingNote != null) pendingNote,
              const SizedBox(height: 10),
              Text(
                '• 식약처 연령금기(DUR) 목록에는 없지만, 약 설명서에 적힌 사용 연령보다 '
                '${child.name}(${child.ageLabel})가 어려요.\n'
                '• 소아과에서는 필요하면 설명서 연령보다 어린 아이에게도 처방할 수 있어요. '
                '임의로 끊지 말고 약사·의사에게 확인해주세요.',
              ),
              const SizedBox(height: 6),
              for (final c in cautions)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text(
                    '"${c.title} 설명서에 \'${c.labelFinding?.evidence ?? ''}\'라고 되어 있는데, '
                    '${child.ageLabel} 아이가 먹어도 되나요?"',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return _Banner(
      color: const Color(0xFFFDE7E7),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFC62828), size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${child.ageLabel} 아이에게 연령금기인 약이 ${dangers.length}개 있어요'
                  '${cautions.isEmpty ? '' : ' (사용 연령 확인 ${cautions.length}개)'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFB71C1C), fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            if (pendingNote != null) pendingNote,
            const SizedBox(height: 10),
            const Text(
              '• 약을 임의로 끊거나 먹이지 말고, 먼저 약국이나 처방한 병원에 전화해 확인하세요.\n'
              '• 의사가 필요하다고 판단해 사유를 적고 처방했을 수도 있어요.\n'
              '• 아래처럼 물어보면 돼요:',
            ),
            const SizedBox(height: 6),
            for (final d in dangers)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text(
                  '"${d.title}이(가) ${_ruleText(d.dangerRows(age))} 연령금기 약으로 '
                  '나오는데, 아이(${child.ageLabel})에게 처방된 이유가 있나요?"',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 종합 결과용 배너: 테두리 없는 진한 배경 (아래 약별 카드와 구분)
class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

String _ruleText(List<TabooRow> rows) =>
    AgeRule.summarize([for (final r in rows) ...r.rule.conditions]);

class _CheckCard extends StatelessWidget {
  const _CheckCard({
    required this.check,
    required this.age,
    required this.onRetry,
    required this.onPick,
  });

  final DrugCheck check;
  final int age;
  final VoidCallback onRetry;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color bg, Color fg, IconData icon, String label) = switch (check.status) {
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
          check.ambiguous ? '약 선택 필요' : '약을 찾지 못함'
        ),
      CheckStatus.unknown => (
          const Color(0xFFFFF4D6),
          const Color(0xFF8A6100),
          Icons.help_outline,
          '내용 확인 필요'
        ),
      CheckStatus.listedOk => (
          const Color(0xFFE8F0FE),
          const Color(0xFF1A56B8),
          Icons.info_outline,
          '연령금기 해당 없음'
        ),
      CheckStatus.notListed => (
          const Color(0xFFE6F4EA),
          const Color(0xFF1E7B3A),
          Icons.check_circle_outline,
          '연령금기 목록에 없음'
        ),
      CheckStatus.error => (
          const Color(0xFFF1F3F4),
          Colors.black87,
          Icons.cloud_off_outlined,
          '조회 실패'
        ),
    };

    final groups = _IngredientGroup.from(check.rows, age);
    final verdict = _verdict(check, age, groups);

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
                    Text(check.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (check.best != null &&
                        check.best!.searchName !=
                            DrugNameExtractor.toSearchName(check.query))
                      Text('입력한 이름: ${check.query}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.black54)),
                    if (check.best != null &&
                        (check.best!.company.isNotEmpty || check.best!.etcOtc.isNotEmpty))
                      Text(
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
                child: Text(label,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ]),
            if (verdict != null) ...[
              const SizedBox(height: 10),
              Text(verdict,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w600, height: 1.4)),
            ],
            if (check.status == CheckStatus.error) ...[
              const SizedBox(height: 8),
              Text(check.error ?? ''),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
            _InfoView(check: check),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (groups.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '성분이 다른 약 ${groups.length}종이 함께 나왔어요. 처방받은 약의 성분 줄만 보세요.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final g in groups) _IngredientView(group: g),
            ],
            if (check.status == CheckStatus.notFound && check.similar.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('비슷한 이름의 약도 없어요. 약봉지의 이름을 다시 확인해 입력해주세요.',
                    style: theme.textTheme.bodySmall),
              ),
            // 약이 확정되면 후보는 보여주지 않는다 (고를 필요가 있을 때만)
            if (check.best == null && check.similar.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(check.ambiguous ? '처방받은 약을 골라주세요' : '혹시 찾으시는 약이 이것인가요?',
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
                                Text(h.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (h.ingredient.isNotEmpty || h.company.isNotEmpty)
                                  Text(
                                    [h.ingredient, h.company]
                                        .where((x) => x.isNotEmpty)
                                        .join(' · '),
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.black54),
                                  ),
                              ],
                            ),
                          ),
                          if (check.tabooNames.contains(h.displayName))
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDE7E7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('연령금기 약',
                                  style: TextStyle(
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
          ],
        ),
      ),
    );
  }

  /// 카드 맨 위에 보여줄 한 줄 결론
  static String? _verdict(DrugCheck c, int age, List<_IngredientGroup> groups) {
    final a = formatAge(age);
    switch (c.status) {
      case CheckStatus.danger:
        final src = AgeRule.summarize([
          for (final g in groups.where((g) => g.applies == true)) ...g.conds
        ]);
        return '우리 아이($a)는 연령금기에 해당해요 (연령금기 기준: $src)';
      case CheckStatus.labelCaution:
        final f = c.labelFinding;
        if (f == null) return null;
        return f.prohibited
            ? '설명서에 "${f.evidence}"라고 되어 있고, 우리 아이($a)가 해당해요.'
            : '설명서에는 "${f.evidence}"에게 쓰는 약으로 되어 있어요. 우리 아이($a)는 이보다 어려요.';
      case CheckStatus.unknown:
        return '연령금기 목록에 있지만 나이 기준이 적혀 있지 않아요. 약사에게 몇 살부터 먹을 수 있는지 확인하세요.';
      case CheckStatus.listedOk:
        return '연령금기 약이지만 우리 아이($a) 나이는 해당하지 않아요.';
      case CheckStatus.notListed:
        return c.info != null
            ? '식약처 연령금기 목록에 없는 약이에요.'
            : '이 이름으로는 연령금기 약을 찾지 못했어요. 이름(오타·띄어쓰기)을 확인해주세요.';
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
        if (reason.length > 1) g.reasons.add(reason);
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
    final (Color c, String tag) = switch (g.applies) {
      true => (const Color(0xFFC62828), '우리 아이 해당'),
      false => (const Color(0xFF1A56B8), '해당 안 됨'),
      null => (const Color(0xFF8A6100), '나이 기준 없음'),
    };
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
          Row(children: [
            Expanded(
              child: Text('성분: ${g.name}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(tag,
                style: TextStyle(
                    color: c, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          if (g.label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('연령금기 기준: ${g.label}',
                style: theme.textTheme.bodyMedium),
          ],
          if (g.ageBase.isNotEmpty)
            Text('(나이 기준 출처: 식약처 DUR 성분정보)',
                style: theme.textTheme.bodySmall),
          if (g.reasons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('사유: ${g.reasons.first}',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          ],
          if (g.applies == true && g.assumed) ...[
            const SizedBox(height: 6),
            Text(
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
          child: Text('약 설명 찾는 중…', style: theme.textTheme.bodySmall),
        );
      }
      if (!check.infoLoading) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('이 이름으로는 약 설명을 찾지 못했어요.',
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
    final String efficacy;
    if (info.efficacy.isNotEmpty) {
      efficacy = _firstSentences(info.efficacy, 140);
    } else if (info.className.isNotEmpty) {
      efficacy = '${info.className} (약 분류)';
    } else {
      efficacy = '식약처 자료에 효능 설명이 없어요.';
    }

    Widget row(String k, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: Text(k,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.black54, height: 1.5)),
              ),
              Expanded(
                child: Text(v,
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
