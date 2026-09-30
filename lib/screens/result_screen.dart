import 'package:flutter/material.dart';

import '../logic/age_rule.dart';
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

    // 같은 품목명+금기내용은 하나로 묶어서 보여준다.
    final seen = <String>{};
    final rows = check.rows.where((r) => seen.add('${r.itemName}|${r.content}')).toList();
    final shown = rows.take(6).toList();

    return Card(
      color: bg,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
            ]),
            _InfoView(check: check),
            if (check.status == CheckStatus.error) ...[
              const SizedBox(height: 8),
              Text(check.error ?? ''),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
            if (check.labelFinding != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  check.labelFinding!.prohibited
                      ? '설명서에 "${check.labelFinding!.evidence}"라고 되어 있어요. '
                          '우리 아이(${formatAge(age)})가 여기에 해당해요.'
                      : '설명서에는 "${check.labelFinding!.evidence}"에게 쓰는 약으로 되어 있어요. '
                          '우리 아이(${formatAge(age)})는 이보다 어려요.',
                  style: const TextStyle(color: Color(0xFF9A3412)),
                ),
              ),
            if (check.rows.isEmpty &&
                (check.status == CheckStatus.notListed ||
                    check.status == CheckStatus.labelCaution))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(check.info != null
                    ? '식약처 연령금기(DUR) 목록에는 없는 약이에요.'
                    : '이 이름으로 등록된 연령금기 품목이 없어요. '
                        '이름이 정확한지(오타·띄어쓰기) 한 번 확인해주세요.'),
              ),
            if (check.matchedQuery != null && check.matchedQuery != check.query)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '"${check.query}"(으)로는 없어서 "${check.matchedQuery}"(으)로 찾은 결과예요. '
                  '처방받은 약과 같은 약인지 이름을 확인해주세요.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (shown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 2),
                child: Row(children: [
                  const Icon(Icons.manage_search, size: 18, color: Colors.black54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '연령금기 목록 검색 결과 · 제품 ${rows.length}개',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: Colors.black54),
                    ),
                  ),
                ]),
              ),
            if (shown.map((r) => r.ingredient).toSet().length > 1)
              Text(
                '이름에 "${check.matchedQuery ?? check.query}"가 들어간 제품이 모두 나왔어요. '
                '성분이 다른 제품도 섞여 있으니 처방받은 약 이름과 같은 줄을 보세요.',
                style: theme.textTheme.bodySmall,
              ),
            for (final r in shown) _RowView(row: r, age: age),
            if (rows.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('외 ${rows.length - shown.length}개 품목이 더 있어요.',
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _RowView extends StatelessWidget {
  const _RowView({required this.row, required this.age});

  final TabooRow row;
  final int age;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final applies = row.rule.appliesTo(age);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.itemName.isEmpty ? '(품목명 없음)' : row.itemName,
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          if (row.company.isNotEmpty || row.ingredient.isNotEmpty)
            Text(
              [row.company, if (row.ingredient.isNotEmpty) '성분: ${row.ingredient}']
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          if (row.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('금기 내용: ${row.content}'),
          ],
          if (row.remark.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('비고: ${row.remark}', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final c in row.rule.conditions) _ruleChip(c),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(applies == true
                  ? '우리 아이 해당'
                  : applies == false
                      ? '우리 아이 해당 안 됨'
                      : '나이 기준 정보 없음'),
            ),
          ]),
          if (row.ageBase.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('나이 기준(식약처 DUR 성분정보): ${row.ageBase}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
          if (applies == null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '식약처 자료에 이 제품의 나이 기준이 적혀 있지 않아요. 연령금기 목록에 올라 있는 약이니, '
                '약사에게 "몇 살부터 먹을 수 있는 약인가요?"라고 꼭 확인하세요.',
                style: TextStyle(color: Color(0xFF7A5200), fontSize: 13),
              ),
            ),
          ],
          if (applies == true && row.rule.conditions.any((c) => c.assumed)) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '판단 사유: 금기 내용에 정확한 연령이 적혀 있지 않지만 '
                '"${_targetWord(row)}"(이)라고 되어 있어, 우리 아이에게 금기인 약품으로 보았어요.',
                style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _targetWord(TabooRow row) {
    final t = '${row.content} ${row.remark}';
    for (final w in ['신생아', '영아', '소아', '어린이', '유아']) {
      if (t.contains(w)) return w;
    }
    return '소아';
  }

  Widget _ruleChip(AgeCondition c) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.block, size: 16),
        label: Text(c.assumed ? c.source : '${c.source} 금기'),
      );
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

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xCCFFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('이 약은 어떤 약?',
              style: theme.textTheme.labelMedium?.copyWith(color: Colors.black54)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.medication_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                info.itemName.isEmpty ? '약 정보' : info.itemName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tags, style: theme.textTheme.bodySmall),
          ],
          if (info.efficacy.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_firstSentences(info.efficacy, 160)),
          ],
          if (info.ingredient.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('성분: ${info.ingredient}', style: theme.textTheme.bodySmall),
          ],
          if (info.usage.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('먹는 방법: ${_firstSentences(info.usage, 120)}',
                style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 4),
          Text('출처: 식약처 ${info.source}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.black45)),
        ],
      ),
    );
  }
}
