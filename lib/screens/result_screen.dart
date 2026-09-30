import 'package:flutter/material.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/dur_api.dart';
import '../logic/models.dart';
import '../logic/storage.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.child, required this.names});

  final ChildProfile child;
  final List<String> names;

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
      for (final q in DrugNameExtractor.searchVariants(c.query)) {
        var rows = await api.searchAgeTaboo(q);
        // 줄인 이름으로 찾을 때는 그 이름으로 "시작하는" 제품만 인정한다.
        // (예: "포타"로 찾으면 "로포타현탁액" 같은 엉뚱한 약이 걸리는 것 방지)
        if (q != c.query) {
          rows = rows.where((r) => r.itemName.startsWith(q)).toList();
        }
        if (rows.isNotEmpty) {
          c.rows = rows;
          c.matchedQuery = q;
          break;
        }
      }
      // 금기 내용에 나이가 없으면 DUR 성분정보에서 성분별 연령 기준을 가져온다.
      await Future.wait(c.rows
          .where((r) =>
              r.ingrCode.isNotEmpty &&
              (!r.rule.isParsed || r.rule.conditions.every((x) => x.assumed)))
          .map((r) async {
        final base = await api.ingredientAgeBase(r.ingrCode);
        if (base.isNotEmpty) r.applyAgeBase(base);
      }));
      c.evaluate(_age);
    } catch (e) {
      c.status = CheckStatus.error;
      c.error = '$e';
    }
    if (mounted) setState(() {});

    // 약 설명은 금기 판정 뒤에 천천히 채운다.
    c.infoLoading = true;
    c.info = null;
    c.labelFinding = null;
    for (final q in DrugNameExtractor.searchVariants(c.query)) {
      final info = await api.searchDrugInfo(q);
      if (info != null && q != c.query && !info.itemName.startsWith(q)) continue;
      if (info != null && !info.isEmpty) {
        c.info = info;
        break;
      }
    }
    c.infoLoading = false;
    if (c.status != CheckStatus.error) c.applyLabel(_age);
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    final api = DurApi(await AppStorage.apiKey());
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
        padding: const EdgeInsets.all(16),
        children: [
          _Summary(
              child: widget.child,
              done: done,
              dangers: dangers,
              cautions: cautions,
              age: _age),
          const SizedBox(height: 12),
          for (final c in sorted)
            _CheckCard(check: c, age: _age, onRetry: () => _retry(c)),
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
      required this.age});

  final ChildProfile child;
  final bool done;
  final List<DrugCheck> dangers;
  final List<DrugCheck> cautions;
  final int age;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!done) {
      return Card(
        child: ListTile(
          leading: const SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          title: Text('${child.name} (${child.ageLabel}) 기준으로 확인 중…'),
        ),
      );
    }
    if (dangers.isEmpty && cautions.isEmpty) {
      return Card(
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
      return Card(
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
                    '"${c.query} 설명서에 \'${c.labelFinding?.evidence ?? ''}\'라고 되어 있는데, '
                    '${child.ageLabel} 아이가 먹어도 되나요?"',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Card(
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
                  '"${d.query}이(가) ${_ruleText(d.dangerRows(age))} 연령금기 약으로 '
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

String _ruleText(List<TabooRow> rows) {
  final parts = <String>{};
  for (final r in rows) {
    for (final c in r.rule.conditions) {
      parts.add(c.source);
    }
  }
  return parts.isEmpty ? '' : parts.join(', ');
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.check, required this.age, required this.onRetry});

  final DrugCheck check;
  final int age;
  final VoidCallback onRetry;

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
          '금기 연령 아님'
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
    final products = <String>{for (final r in check.rows) r.itemName}.toList();
    final verdict = _verdict(check, age, groups);

    return Card(
      color: bg,
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
                child: Text(check.query,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                    '"${check.matchedQuery ?? check.query}"(으)로 성분이 다른 약 ${groups.length}종이 함께 나왔어요. '
                    '처방받은 약의 성분 줄만 보세요.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              for (final g in groups) _IngredientView(group: g),
            ],
            if (check.matchedQuery != null && check.matchedQuery != check.query)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '"${check.query}"(으)로는 없어서 "${check.matchedQuery}"(으)로 찾은 결과예요. '
                  '처방받은 약과 같은 약인지 확인해주세요.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (products.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text('관련 제품 ${products.length}개 보기',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.black54)),
                  children: [
                    for (final n in products)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text('· $n', style: theme.textTheme.bodySmall),
                        ),
                      ),
                  ],
                ),
              ),
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
        final src = <String>{
          for (final g in groups.where((g) => g.applies == true)) ...g.conditions
        };
        return '우리 아이($a)는 연령금기에 해당해요: ${src.join(', ')}';
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
  final Set<String> conditions = {};
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
          g.conditions.add(c.source);
          if (c.assumed) g.assumed = true;
        }
        final reason = r.content.replaceAll(RegExp(r'^[\s_\-]+|[\s_\-]+$'), '');
        if (reason.length > 1) g.reasons.add(reason);
        if (r.ageBase.isNotEmpty) g.ageBase = r.ageBase;
      }
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
        color: Colors.white,
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
          if (g.conditions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('금기 연령: ${g.conditions.join(', ')}',
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

    final tags = [
      if (info.className.isNotEmpty) info.className,
      if (info.etcOtc.isNotEmpty) info.etcOtc,
    ].join(' · ');
    final desc = info.efficacy.isNotEmpty
        ? _firstSentences(info.efficacy, 120)
        : [
            if (tags.isNotEmpty) tags,
            if (info.ingredient.isNotEmpty) '성분 ${info.ingredient}',
          ].join(' · ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xCCFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.medication_outlined, size: 18, color: Colors.black54),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('어떤 약?',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.black54)),
                const SizedBox(height: 2),
                Text(desc.isEmpty ? info.itemName : desc,
                    style: const TextStyle(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
