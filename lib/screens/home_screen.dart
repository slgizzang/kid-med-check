import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';
import 'child_edit_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ChildProfile> _children = [];
  List<MedRecord> _records = [];
  String? _selectedId;
  bool _hasKey = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final children = await AppStorage.children();
    final records = await AppStorage.records();
    final sel = await AppStorage.selectedChildId();
    final key = await AppStorage.apiKey();
    if (!mounted) return;
    setState(() {
      _children = children;
      _records = records..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _selectedId = children.any((c) => c.id == sel)
          ? sel
          : (children.isNotEmpty ? children.first.id : null);
      _hasKey = key.isNotEmpty;
      _loading = false;
    });
  }

  ChildProfile? get _selected {
    for (final c in _children) {
      if (c.id == _selectedId) return c;
    }
    return null;
  }

  List<MedRecord> get _myRecords =>
      _records.where((r) => r.childId == _selectedId).toList();

  Future<void> _editChild([ChildProfile? child]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ChildEditScreen(child: child)),
    );
    if (changed == true) await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    await _load();
  }

  Future<void> _openRecord(MedRecord r) async {
    final child = _selected;
    if (child == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecordScreen(child: child, record: r)),
    );
    await _load();
  }

  Future<void> _newRecord() async {
    final child = _selected;
    if (child == null) {
      await _editChild();
      return;
    }
    final now = DateTime.now();
    final r = MedRecord(
      id: now.microsecondsSinceEpoch.toString(),
      childId: child.id,
      title: MedRecord.defaultTitle(now),
      createdAt: now,
    );
    await AppStorage.saveRecord(r);
    await _openRecord(r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (!_hasKey) _keyBanner(),
                      SectionTitle('누구의 약인가요?',
                          trailing: _children.isEmpty
                              ? null
                              : Text('길게 눌러 수정',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.sub))),
                      _childRow(),
                      const SizedBox(height: 28),
                      SectionTitle('처방 기록',
                          trailing: _selected == null
                              ? null
                              : Text('${_myRecords.length}개',
                                  style: const TextStyle(color: AppColors.sub))),
                      ..._recordList(),
                      const SizedBox(height: 20),
                      _notice(),
                    ]),
                  ),
                ),
              ],
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _newRecord,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              highlightElevation: 0,
              icon: const Icon(Icons.add),
              label: Text(_selected == null ? '아이 등록하기' : '새 처방 기록',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 18, 8, 4),
      child: Row(
        children: [
          const AppLogo(size: 46),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kAppName,
                    style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                SizedBox(height: 2),
                Text(kAppTagline,
                    style: TextStyle(color: AppColors.sub, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            tooltip: '설정',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined, color: AppColors.sub),
          ),
        ],
      ),
    );
  }

  Widget _keyBanner() => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          color: const Color(0xFFFDECEC),
          child: ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: const Text('인증키 설정이 필요해요'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openSettings,
          ),
        ),
      );

  Widget _childRow() {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in _children)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _ChildCard(
                child: c,
                selected: c.id == _selectedId,
                onTap: () {
                  setState(() => _selectedId = c.id);
                  AppStorage.setSelectedChildId(c.id);
                },
                onLongPress: () => _editChild(c),
              ),
            ),
          _AddChildCard(onTap: () => _editChild()),
        ],
      ),
    );
  }

  List<Widget> _recordList() {
    if (_selected == null) {
      return [
        _EmptyBox(
          icon: Icons.child_care,
          text: '먼저 아이 이름과 생년월일을 등록해주세요.',
          action: FilledButton.tonal(
              onPressed: () => _editChild(), child: const Text('아이 등록')),
        ),
      ];
    }
    final list = _myRecords;
    if (list.isEmpty) {
      return [
        const _EmptyBox(
          icon: Icons.receipt_long_outlined,
          text: '아직 처방 기록이 없어요.\n아래 "새 처방 기록"을 눌러 약봉지를 찍어보세요.',
        ),
      ];
    }
    return [
      for (final r in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RecordCard(record: r, onTap: () => _openRecord(r)),
        ),
    ];
  }

  Widget _notice() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: AppColors.primaryDark, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '식약처 DUR "특정연령대 금기"와 약 설명서의 사용 연령을 아이 나이와 비교해요. '
                '경고가 나와도 약을 임의로 끊지 말고 약국·병원에 꼭 확인하세요.',
                style: TextStyle(color: AppColors.primaryDark, height: 1.45),
              ),
            ),
          ],
        ),
      );
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final ChildProfile child;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppColors.primary : AppColors.line),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: selected ? Colors.white : AppColors.mint,
            child: Text(
              child.name.isEmpty ? '?' : child.name.characters.first,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: selected ? AppColors.primary : AppColors.primaryDark),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(child.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: selected ? Colors.white : AppColors.ink)),
                const SizedBox(height: 2),
                Text(child.ageLabel,
                    style: TextStyle(
                        fontSize: 13,
                        color: selected ? const Color(0xDDFFFFFF) : AppColors.sub)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _AddChildCard extends StatelessWidget {
  const _AddChildCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 92,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_alt_1_outlined, color: AppColors.primary),
            SizedBox(height: 4),
            Text('아이 추가', style: TextStyle(fontSize: 13, color: AppColors.sub)),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onTap});

  final MedRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final names = record.drugs;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.medication_outlined,
                  color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.ink)),
                  const SizedBox(height: 3),
                  Text(
                    names.isEmpty
                        ? '${formatDate(record.createdAt)} · 약 없음'
                        : '${formatDate(record.createdAt)} · 약 ${names.length}개',
                    style: const TextStyle(fontSize: 13, color: AppColors.sub),
                  ),
                  if (names.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      names.take(3).join(', ') +
                          (names.length > 3 ? ' 외 ${names.length - 3}개' : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.ink),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.sub),
          ]),
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: [
        Icon(icon, size: 40, color: const Color(0xFFB7C9C3)),
        const SizedBox(height: 10),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.sub, height: 1.5)),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]),
    );
  }
}
