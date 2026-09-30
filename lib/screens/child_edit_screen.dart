import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';

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
  bool _pregnant = false;
  bool _nursing = false;

  bool get _isAdult =>
      _birth != null && monthsBetween(_birth!, DateTime.now()) >= 19 * 12;

  @override
  void initState() {
    super.initState();
    _birth = widget.child?.birthDate;
    _pregnant = widget.child?.pregnant ?? false;
    _nursing = widget.child?.nursing ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  /// 년·월·일을 각각 굴려서 고르는 휠 (월도 한 번에 선택 가능)
  Future<void> _pickDate() async {
    final now = DateTime.now();
    var temp = _birth ?? DateTime(now.year - 3, now.month, now.day);
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const KText('생년월일',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(
                height: 220,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  dateOrder: DatePickerDateOrder.ymd,
                  initialDateTime: temp,
                  minimumDate: DateTime(now.year - 100),
                  maximumDate: now,
                  onDateTimeChanged: (d) => temp = d,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, temp),
                child: const KText('확인'),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() => _birth = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _birth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KText('이름과 생년월일을 입력해주세요.')));
      return;
    }
    final list = await AppStorage.children();
    final id = widget.child?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final updated = ChildProfile(
      id: id,
      name: name,
      birthDate: _birth!,
      pregnant: _isAdult && _pregnant,
      nursing: _isAdult && _nursing,
    );
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
        title: const KText('삭제할까요?'),
        content: const KText('이 사람의 처방 기록도 함께 지워져요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const KText('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const KText('삭제')),
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
        title: KText(widget.child == null ? '가족 추가' : '정보 수정'),
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
            label: KText(birth == null
                ? '생년월일 선택'
                : '${_fmt(birth)}  (${formatAge(monthsBetween(birth, DateTime.now()))})'),
            onPressed: _pickDate,
          ),
          const SizedBox(height: 8),
          const KText('나이는 만 나이(개월)로 계산해 금기 기준과 비교해요.'),
          if (_isAdult) ...[
            const SizedBox(height: 20),
            const KText('성인이면 함께 확인해요',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const KText('임신 중'),
              subtitle: const KText('식약처 DUR 임부금기 약을 알려드려요'),
              value: _pregnant,
              onChanged: (v) => setState(() => _pregnant = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const KText('수유 중'),
              subtitle: const KText('약 설명서의 수유부 주의사항을 알려드려요'),
              value: _nursing,
              onChanged: (v) => setState(() => _nursing = v),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _save,
            child: const KText('저장'),
          ),
        ],
      ),
    );
  }
}
