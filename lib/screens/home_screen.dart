import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';
import 'child_edit_screen.dart';
import 'import_screen.dart';
import 'reaction_list_screen.dart';
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

  /// 처방 기록 여러 개 선택해서 지우기
  bool _selecting = false;
  final Set<String> _picked = {};
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

  Future<void> _deletePicked() async {
    final n = _picked.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: KText('처방 기록 $n개를 지울까요?'),
        content: const KText('지운 기록은 되돌릴 수 없어요. 적어둔 복용 후 반응 기록은 남아요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const KText('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const KText('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _picked.toList()) {
      await AppStorage.deleteRecord(id);
    }
    _picked.clear();
    _selecting = false;
    await _load();
  }

  Future<void> _openImport() async {
    final person = _selected;
    if (person == null) return;
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => ImportScreen(person: person)));
    if (changed == true) await _load();
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
                              : KText('길게 눌러 수정',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.sub))),
                      _childRow(),
                      const SizedBox(height: 28),
                      SectionTitle('처방 기록',
                          trailing: _selected == null || _myRecords.isEmpty
                              ? null
                              : TextButton(
                                  onPressed: () => setState(() {
                                    _selecting = !_selecting;
                                    _picked.clear();
                                  }),
                                  child: KText(_selecting ? '완료' : '선택',
                                      maxLines: 1),
                                )),
                      ..._recordList(),
                      const SizedBox(height: 20),
                      _notice(),
                    ]),
                  ),
                ),
              ],
            ),
      floatingActionButton: _loading || _selected == null || _myRecords.isEmpty || _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: _newRecord,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              highlightElevation: 0,
              icon: const Icon(Icons.add),
              label: KText('새 처방 기록',
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
                KText(kAppName,
                    style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                SizedBox(height: 2),
                KText(kAppTagline,
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
            title: const KText('인증키 설정이 필요해요'),
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
                  setState(() {
                    _selectedId = c.id;
                    _selecting = false;
                    _picked.clear();
                  });
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
        const _EmptyBox(
          icon: Icons.person_outline,
          text: '위의 "복용자 추가"로 약을 먹을 사람을 먼저 등록해주세요.',
        ),
      ];
    }
    final list = _myRecords;
    final importButton = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _openImport,
        icon: const Icon(Icons.history, size: 20),
        label: const KText('지난 1년 기록 불러오기'),
      ),
    );
    final reactionsButton = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ReactionListScreen(person: _selected!))),
        icon: const Icon(Icons.edit_note, size: 20),
        label: const KText('복용 후 반응 기록 모아보기'),
      ),
    );
    if (list.isEmpty) {
      return [
        importButton,
        reactionsButton,
        _EmptyBox(
          icon: Icons.add_circle_outline,
          text: '아직 처방 기록이 없어요.\n여기를 눌러 처방받은 약을 입력해보세요.',
          onTap: _newRecord,
        ),
      ];
    }
    final allPicked = list.isNotEmpty && list.every((r) => _picked.contains(r.id));
    return [
      if (!_selecting) importButton,
      if (!_selecting) reactionsButton,
      if (_selecting)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Checkbox(
              value: allPicked ? true : (_picked.isEmpty ? false : null),
              tristate: true,
              onChanged: (_) => setState(() {
                if (allPicked) {
                  _picked.clear();
                } else {
                  _picked.addAll(list.map((r) => r.id));
                }
              }),
            ),
            const KText('전체 선택', maxLines: 1),
            const Spacer(),
            TextButton.icon(
              onPressed: _picked.isEmpty ? null : _deletePicked,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC62828)),
              icon: const Icon(Icons.delete_outline, size: 20),
              label: KText('삭제 ${_picked.length}개', maxLines: 1),
            ),
          ]),
        ),
      for (final r in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RecordCard(
            record: r,
            selecting: _selecting,
            selected: _picked.contains(r.id),
            onTap: _selecting
                ? () => setState(() =>
                    _picked.contains(r.id) ? _picked.remove(r.id) : _picked.add(r.id))
                : () => _openRecord(r),
          ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OneLine('식약처 공공데이터로 복용자 정보에 맞춰 확인해요.'),
                  _OneLine('금기 정보는 의약품안전사용서비스(DUR),'),
                  _OneLine('효능과 주의사항은 e약은요,'),
                  _OneLine('성분과 전문·일반 구분은 제품 허가정보를 써요.'),
                  SizedBox(height: 6),
                  _OneLine('경고가 나와도 임의로 끊지 말고 약사·의사와 상의하세요.'),
                ],
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
            child: KText(
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
                KText(child.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: selected ? Colors.white : AppColors.ink)),
                const SizedBox(height: 2),
                KText(child.ageLabel,
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
            KText('복용자 추가', style: TextStyle(fontSize: 13, color: AppColors.sub)),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final MedRecord record;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;

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
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: selected ? AppColors.primary : AppColors.sub,
                  size: 26,
                ),
              )
            else
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
                  KText(record.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.ink)),
                  const SizedBox(height: 3),
                  KText(
                    names.isEmpty
                        ? '${formatDate(record.createdAt)} · 약 없음'
                        : '${formatDate(record.createdAt)} · 약 ${names.length}개',
                    style: const TextStyle(fontSize: 13, color: AppColors.sub),
                  ),
                  if (names.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    KText(
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
            if (!selecting) const Icon(Icons.chevron_right, color: AppColors.sub),
          ]),
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.text, this.action, this.onTap});

  final IconData icon;
  final String text;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onTap != null ? AppColors.primary : AppColors.line),
      ),
      child: Column(children: [
        Icon(icon, size: 40,
            color: onTap != null ? AppColors.primary : const Color(0xFFB7C9C3)),
        const SizedBox(height: 10),
        KText(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.sub, height: 1.5)),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]),
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
          borderRadius: BorderRadius.circular(18), onTap: onTap, child: box),
    );
  }
}

const _noticeStyle = TextStyle(color: AppColors.primaryDark, height: 1.45);

/// 한 줄에 다 들어가게 (화면이 좁으면 글자를 살짝 줄임)
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, softWrap: false, style: _noticeStyle),
      );
}
