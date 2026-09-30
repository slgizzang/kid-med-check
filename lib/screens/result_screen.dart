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
        final rows = await api.searchAgeTaboo(q);
        if (rows.isNotEmpty) {
          c.rows = rows;
          c.matchedQuery = q;
          break;
        }
      }
      c.evaluate(_age);
    } catch (e) {
      c.status = CheckStatus.error;
      c.error = '$e';
    }
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
    final done = _checks.every((c) => c.status != CheckStatus.loading);
    final dangers = _checks.where((c) => c.status == CheckStatus.danger).toList();
    final order = [
      CheckStatus.danger,
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
              child: widget.child, done: done, dangers: dangers, age: _age),
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
      required this.age});

  final ChildProfile child;
  final bool done;
  final List<DrugCheck> dangers;
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
    if (dangers.isEmpty) {
      return Card(
        color: const Color(0xFFE6F4EA),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${child.name}(${child.ageLabel}) 나이에 연령금기로 등록된 약은 찾지 못했어요.\n'
            '노란색·회색 항목이 있다면 내용을 한 번 더 확인해주세요.',
            style: theme.textTheme.bodyLarge,
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
                  '${child.ageLabel} 아이에게 연령금기인 약이 ${dangers.length}개 있어요',
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
            if (check.status == CheckStatus.error) ...[
              const SizedBox(height: 8),
              Text(check.error ?? ''),
              TextButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
            if (check.status == CheckStatus.notListed)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('이 이름으로 등록된 연령금기 품목이 없어요. '
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
                      : '연령 자동판단 불가'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _ruleChip(AgeCondition c) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.block, size: 16),
        label: Text('${c.source} 금기'),
      );
}
