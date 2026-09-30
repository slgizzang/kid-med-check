import 'package:flutter/material.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/models.dart';

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
  _Entry(this.name);
  String name;
  bool checked = true;
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  late final List<_Entry> _entries =
      widget.initialNames.map((n) => _Entry(n)).toList();
  final _input = TextEditingController();

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
        title: const Text('약 이름 수정'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('확인')),
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
          const SnackBar(content: Text('추가할 약 이름을 하나 이상 선택해주세요.')));
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
      appBar: AppBar(title: const Text('사진에서 찾은 약')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Text(
            '${widget.child.name} (${widget.child.ageLabel})',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.rawText.isEmpty
                ? '처방전이나 약봉지에 적힌 약 이름을 입력해주세요.'
                : '사진에서 찾은 이름이에요. 틀린 글자는 눌러서 고치고, 약이 아닌 건 체크를 빼주세요.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (widget.rawText.isNotEmpty && _entries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('약 이름을 찾지 못했어요. 아래에 직접 입력하거나, '
                    '더 밝고 가까이에서 다시 찍어주세요.'),
              ),
            ),
          for (final e in _entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: CheckboxListTile(
                value: e.checked,
                onChanged: (v) => setState(() => e.checked = v ?? false),
                title: Text(e.name),
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
              title: const Text('인식된 전체 글자 보기'),
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
            label: Text('$count개 약 기록에 추가'),
            onPressed: _check,
          ),
        ),
      ),
    );
  }
}
