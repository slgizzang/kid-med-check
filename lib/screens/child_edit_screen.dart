import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/storage.dart';

class ChildEditScreen extends StatefulWidget {
  const ChildEditScreen({super.key, this.child});

  final ChildProfile? child;

  @override
  State<ChildEditScreen> createState() => _ChildEditScreenState();
}

class _ChildEditScreenState extends State<ChildEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.child?.name ?? '');
  DateTime? _birth;

  @override
  void initState() {
    super.initState();
    _birth = widget.child?.birthDate;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 5, now.month, now.day),
      firstDate: DateTime(now.year - 25),
      lastDate: now,
      helpText: '생년월일 선택',
      initialEntryMode: DatePickerEntryMode.calendar,
    );
    if (picked != null) setState(() => _birth = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _birth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이름과 생년월일을 입력해주세요.')));
      return;
    }
    final list = await AppStorage.children();
    final id = widget.child?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final updated = ChildProfile(id: id, name: name, birthDate: _birth!);
    final idx = list.indexWhere((c) => c.id == id);
    if (idx >= 0) {
      list[idx] = updated;
    } else {
      list.add(updated);
    }
    await AppStorage.saveChildren(list);
    await AppStorage.setSelectedChildId(id);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제할까요?'),
        content: const Text('이 아이의 처방 기록도 함께 지워져요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    final list = await AppStorage.children();
    list.removeWhere((c) => c.id == widget.child!.id);
    await AppStorage.saveChildren(list);
    await AppStorage.deleteRecordsOfChild(widget.child!.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final birth = _birth;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.child == null ? '아이 정보 추가' : '아이 정보 수정'),
        actions: [
          if (widget.child != null)
            IconButton(
                tooltip: '삭제',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '이름 또는 별명',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.cake_outlined),
            label: Text(birth == null
                ? '생년월일 선택'
                : '${_fmt(birth)}  (${formatAge(monthsBetween(birth, DateTime.now()))})'),
            onPressed: _pickDate,
          ),
          const SizedBox(height: 8),
          const Text('나이는 만 나이(개월)로 계산해 금기 기준과 비교해요.'),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _save,
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}
