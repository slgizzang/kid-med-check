import 'package:flutter/material.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/dur_api.dart';
import '../logic/storage.dart';
import '../logic/models.dart';
import '../ui/theme.dart';

/// OCR로 뽑은 약 이름 후보를 확인·수정하고, 직접 추가하는 화면
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({
    super.key,
    required this.child,
    required this.initialNames,
    required this.rawText,
  });

  final ChildProfile child;
  final List<String> initialNames;
  final String rawText;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _Entry {
  _Entry(this.name, {this.checked = true});
  String name;
  bool checked;

  /// 식약처 자료에서 실제 약으로 확인됐는지 (null = 확인 중)
  bool? verified;

  /// 확인된 제품명
  String? product;
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late final List<_Entry> _entries =
      widget.initialNames.map((n) => _Entry(n, checked: false)).toList();
  final _input = TextEditingController();
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    if (widget.rawText.isNotEmpty && _entries.isNotEmpty) _verify();
  }

  /// 사진 전체에서 뽑은 후보 중 실제 약 이름만 골라 체크한다 (식약처 품목 자료와 대조)
  Future<void> _verify() async {
    setState(() => _verifying = true);
    final api = DurApi(await AppStorage.apiKey());
    final list = List.of(_entries);
    for (var i = 0; i < list.length; i += 6) {
      await Future.wait(list.skip(i).take(6).map((e) async {
        final q = DrugNameExtractor.toSearchName(e.name);
        try {
          final hits = await api.searchProducts(q);
          final match = hits.where((h) => h.searchName.startsWith(q) || q.startsWith(h.searchName));
          e.verified = match.isNotEmpty;
          if (match.isNotEmpty) e.product = match.first.displayName;
        } catch (_) {
          e.verified = null;
        }
        e.checked = e.verified == true;
        if (mounted) setState(() {});
      }));
    }
    // 확인된 약을 위로
    _entries.sort((a, b) => (b.verified == true ? 1 : 0) - (a.verified == true ? 1 : 0));
    if (mounted) setState(() => _verifying = false);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final names = DrugNameExtractor.splitManual(_input.text);
    if (names.isEmpty) return;
    setState(() {
      for (final n in names) {
        if (!_entries.any((e) => e.name == n)) _entries.add(_Entry(n));
      }
      _input.clear();
    });
  }

  Future<void> _edit(_Entry e) async {
    final c = TextEditingController(text: e.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const KText('약 이름 수정'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const KText('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const KText('확인')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) setState(() => e.name = v);
  }

  void _check() {
    if (_input.text.trim().isNotEmpty) _add();
    final names = _entries
        .where((e) => e.checked)
        .map((e) => DrugNameExtractor.toSearchName(e.name))
        .where((n) => n.length >= 2)
        .toSet()
        .toList();
    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KText('추가할 약 이름을 하나 이상 선택해주세요.')));
      return;
    }
    // 처방 기록 화면으로 돌려준다 (기록에 저장됨)
    Navigator.pop(context, names);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _entries.where((e) => e.checked).length;
    return Scaffold(
      appBar: AppBar(title: const KText('사진에서 찾은 약')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          KText(
            '${widget.child.name} (${widget.child.ageLabel})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          KText(
            widget.rawText.isEmpty
                ? '처방받은 약 이름을 입력해주세요.'
                : _verifying
                    ? '사진에서 찾은 글자 중 실제 약 이름을 식약처 자료로 확인하는 중이에요…'
                    : '식약처 자료로 확인된 약만 골라 두었어요. 빠진 약은 체크하거나 아래에서 직접 추가해주세요.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (widget.rawText.isNotEmpty && _entries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: KText('약 이름을 찾지 못했어요. 아래에 직접 입력하거나, '
                    '더 밝고 가까이에서 다시 찍어주세요.'),
              ),
            ),
          for (final e in _entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: CheckboxListTile(
                value: e.checked,
                onChanged: (v) => setState(() => e.checked = v ?? false),
                title: KText(e.name),
                subtitle: e.verified == null
                    ? (_verifying ? const KText('확인 중…', style: TextStyle(fontSize: 12)) : null)
                    : KText(
                        e.verified! ? '확인됨 · ${e.product ?? ''}' : '약 목록에서 찾지 못함',
                        style: TextStyle(
                            fontSize: 12,
                            color: e.verified! ? AppColors.primaryDark : AppColors.sub),
                      ),
                secondary: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(e),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(
                    labelText: '약 이름 추가 (예: 타이레놀정)',
                    helperText: '여러 개는 쉼표로 구분',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  onPressed: _add, icon: const Icon(Icons.add)),
            ],
          ),
          if (widget.rawText.isNotEmpty) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              title: const KText('인식된 전체 글자 보기'),
              childrenPadding: const EdgeInsets.all(12),
              children: [SelectableText(widget.rawText)],
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.playlist_add),
            label: KText('$count개 약 기록에 추가'),
            onPressed: _check,
          ),
        ),
      ),
    );
  }
}
