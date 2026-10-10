import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/recall.dart';
import '../logic/silson24.dart';
import '../logic/storage.dart';
import '../ui/dashboard.dart' show kNoteBg, kNoteFg;
import '../ui/recall_card.dart';
import '../ui/claim_summary.dart';
import '../ui/sources_note.dart';
import '../ui/summary_card.dart';
import '../ui/theme.dart';
import 'child_edit_screen.dart';
import 'import_screen.dart';
import 'reaction_list_screen.dart';
import 'result_screen.dart';
import 'report_screen.dart';
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
  Map<String, int> _reactionCount = {};

  /// 복용 기록 여러 개 선택해서 함께 확인하거나 지우기
  bool _selecting = false;
  final Set<String> _picked = {};
  String? _selectedId;
  bool _hasKey = true;
  bool _loading = true;

  /// 목록이 길 때 맨 위로 바로 올라가는 버튼
  final _scroll = ScrollController();
  bool _showTop = false;

  @override
  void dispose() {
    for (final t in _autoTimers.values) {
      t.cancel();
    }
    AppStorage.placesChanged.removeListener(_onPlaces);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > 600;
    if (show != _showTop) setState(() => _showTop = show);
  }

  void _toTop() => _scroll.animateTo(0,
      duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _autoReady = true);
    });
    _backfillPlaces();
    AppStorage.placesChanged.addListener(_onPlaces);
  }

  void _onPlaces() {
    if (mounted) _load();
  }

  /// 예전에 불러온 기록 중 병원·약국 위치가 없는 것을 뒤에서 한 번 채운다 (앱 실행마다 한 번)
  static bool _backfilled = false;
  Future<void> _backfillPlaces() async {
    if (_backfilled) {
      _placesReady = true;
      return;
    }
    _backfilled = true;
    try {
      final n = await AppStorage.fillPlaces();
      if (n > 0 && mounted) await _load();
    } catch (_) {}
    _placesReady = true;
    _runSilson();
  }

  /// 병원·약국 위치 채우기가 끝났는지 (실손24 연계는 위치까지 안 뒤에 한 번에 확인해야 정확하고 한꺼번에 나온다)
  bool _placesReady = false;

  Future<void> _load() async {
    final children = await AppStorage.children();
    final notes = await AppStorage.allReactions();
    final counts = <String, int>{};
    for (final n in notes) {
      counts[n.childId] = (counts[n.childId] ?? 0) + 1;
    }
    _reactionCount = counts;
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
    _loadRecalls(key);
    _runSilson();
  }

  /// 식약처 회수 목록 (하루 한 번 받음)
  List<Recall> _recalls = const [];

  Future<void> _loadRecalls(String key) async {
    final list = await RecallStore.load(key);
    if (mounted && list.isNotEmpty) setState(() => _recalls = list);
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
        title: KText('복용 기록 $n개를 지울까요?'),
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

  /// 고른 기록들의 약 (같은 약은 한 번만) → 어느 기록의 약인지
  Map<String, String> get _pickedDrugs {
    final out = <String, List<String>>{};
    // 오래된 기록부터 모아 표시 순서를 날짜순으로
    final recs = _myRecords.where((r) => _picked.contains(r.id)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final r in recs) {
      for (final d in r.drugs) {
        final name = d.trim();
        if (name.isEmpty) continue;
        (out[name] ??= []).add(r.title);
      }
    }
    return {for (final e in out.entries) e.key: e.value.toSet().join(', ')};
  }

  /// 고른 기록의 약을 모두 모아 함께 먹어도 되는지(병용금기) 확인
  Future<void> _checkTogether() async {
    final person = _selected;
    final drugs = _pickedDrugs;
    if (person == null || drugs.length < 2) return;
    final recs = _myRecords.where((r) => _picked.contains(r.id)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final letters = {for (final r in recs) ...r.safetyLetters};
    final recalls = {for (final h in matchRecalls(recs, _recalls)) h.drug: h};
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          child: person,
          names: drugs.keys.toList(),
          title: '함께 먹는 약 확인',
          origins: drugs,
          letters: letters,
          recalls: recalls,
        ),
      ),
    );
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
    // 병원 처방약인지 약국에서 산 약인지 먼저 고른다
    final otc = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const KText('어떤 약인가요?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 12),
            _KindOption(
              otc: false,
              title: '병원에서 처방받은 약',
              sub: '처방전·약봉지의 약',
              onTap: () => Navigator.pop(ctx, false),
            ),
            const SizedBox(height: 8),
            _KindOption(
              otc: true,
              title: '약국에서 직접 산 약',
              sub: '처방 없이 산 일반의약품',
              onTap: () => Navigator.pop(ctx, true),
            ),
          ]),
        ),
      ),
    );
    if (otc == null) return;
    final now = DateTime.now();
    final r = MedRecord(
      id: now.microsecondsSinceEpoch.toString(),
      childId: child.id,
      title: MedRecord.defaultTitle(now, otc: otc),
      createdAt: now,
      otc: otc,
    );
    await AppStorage.saveRecord(r);
    await _openRecord(r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          // 자동 안전 확인은 화면 밖(Offstage)에서 돈다. 크기는 목록이 화면을 꽉 채우게 (expand)
          : Stack(fit: StackFit.expand, children: [
              Positioned.fill(child: _scrollBody()),
              ..._autoCheckers(),
            ]),
      bottomNavigationBar: _selecting ? _togetherBar() : null,
      floatingActionButton: _fab(),
    );
  }

  Widget _scrollBody() => CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _header()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (!_hasKey) _keyBanner(),
                      // 복용자 고르기: 아래 기록 영역과 구분되도록 색 있는 패널로 묶는다
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 0, 16),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 16, bottom: 10),
                            child: Row(children: [
                              const Icon(Icons.people_alt_outlined,
                                  size: 20, color: AppColors.primaryDark),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: KText('누구의 약인가요?',
                                    maxLines: 1,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primaryDark)),
                              ),
                              if (_children.isNotEmpty)
                                const KText('길게 눌러 수정',
                                    maxLines: 1,
                                    style: TextStyle(fontSize: 12, color: AppColors.sub)),
                            ]),
                          ),
                          _childRow(),
                        ]),
                      ),
                      const SizedBox(height: 28),
                      if (_selected != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: KText('${_selected!.name}님의 복용 기록',
                              maxLines: 1,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                        ),
                      if (_selected != null)
                        SafetySummaryCard(
                          records: _myRecords,
                          person: _selected!,
                          recallCount: matchRecalls(_checkedRecords, _recalls).length,
                          letterCount: letterHits(_checkedRecords).length,
                          recallRecords: _byRecord([
                            for (final h in matchRecalls(_checkedRecords, _recalls)) (h.record, h.drug)
                          ]),
                          letterRecords:
                              _byRecord([for (final h in letterHits(_checkedRecords)) (h.record, h.drug)]),
                          onOpen: (r) => _openResult(context, r),
                          checking: _unchecked.where((r) => !_gaveUp(r.id)).length,
                          failed: _unchecked.where((r) => _gaveUp(r.id)).length,
                          onRetry: _retryFailed,
                        ),
                      if (_selected != null && kShowSilson24)
                        ClaimSummaryCard(
                            records: _myRecords, checking: !_silsonDone, onOpen: _openRecord),
                      if (_selected != null && !_selecting) ...[
                        const SectionTitle('기록 추가'),
                        _addRow(),
                        const SizedBox(height: 28),
                      ],
                      SectionTitle('기록 목록',
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
            );

  Widget _fab() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 많이 내려왔을 때만 보이는 '맨 위로'
          AnimatedScale(
            scale: _showTop ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: FloatingActionButton.small(
              heroTag: 'toTop',
              tooltip: '맨 위로',
              onPressed: _toTop,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.ink,
              elevation: 2,
              shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
              child: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ],
      );

  /// 선택 중일 때 아래 고정 버튼: 고른 기록의 약끼리 병용금기 확인
  Widget _togetherBar() {
    final n = _pickedDrugs.length;
    final ok = n >= 2;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          KText(
            ok
                ? '고른 기록의 약 $n개를 ${_selected?.name ?? ''}님 지금 나이로 함께 확인해요.'
                : '함께 먹는 약이 든 기록을 골라주세요. (약 2개 이상)',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.sub),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: ok ? _checkTogether : null,
              icon: const Icon(Icons.compare_arrows),
              label: KText(ok ? '함께 먹어도 되는지 확인 · 약 $n개' : '함께 먹어도 되는지 확인',
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ]),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(kAppName,
                        style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(kAppSlogan,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                              color: AppColors.brand,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 0.1)),
                    ),
                  ],
                ),
                SizedBox(height: 2),
                KText(kAppTagline,
                    maxLines: 1,
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
    if (list.isEmpty) {
      return [
        const _EmptyBox(
          icon: Icons.inventory_2_outlined,
          text: '아직 복용 기록이 없어요. 위의 "기록 추가"에서 시작해보세요.',
        ),
      ];
    }
    final allPicked = list.isNotEmpty && list.every((r) => _picked.contains(r.id));
    return [
      if (!_selecting) _viewsRow(),
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
            status: _statusOf(r),
            claim: _claimChip(r),
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

  /// (기록, 약) 목록을 기록별로 묶는다: 같은 기록의 약 이름은 이어 붙여 한 줄로
  List<(MedRecord, String)> _byRecord(List<(MedRecord, String)> items) {
    final m = <MedRecord, List<String>>{};
    for (final (r, d) in items) {
      (m[r] ??= []).add(d);
    }
    return [for (final e in m.entries) (e.key, e.value.toSet().join(', '))];
  }

  /// 안전 확인을 마친(약이 바뀌지 않은) 기록 — 금기·회수·주의 알림은 이 기록들만 보여준다
  List<MedRecord> get _checkedRecords =>
      [for (final r in _myRecords) if (r.last != null && r.last!.matches(r.drugs)) r];

  /// 자동 안전 확인: 기록을 추가하거나 불러오면 뒤에서 몇 건씩 동시에 확인해 저장한다.
  /// 실패하거나(인터넷 등) 너무 오래 걸린 기록은 잠시 뒤 다시 시도하고, 3번 실패하면
  /// '확인하지 못한 기록'으로 알려 사용자가 다시 확인을 누를 수 있게 한다.
  static const _maxTries = 3;
  final Map<String, int> _fails = {};
  final Map<String, DateTime> _retryAt = {};

  bool _gaveUp(String id) => (_fails[id] ?? 0) >= _maxTries;
  bool _waiting(String id) => _retryAt[id]?.isAfter(DateTime.now()) ?? false;

  void _failed(String id) {
    if (!mounted) return;
    setState(() {
      final n = (_fails[id] ?? 0) + 1;
      _fails[id] = n;
      if (n < _maxTries) {
        final wait = Duration(seconds: 10 * n);
        _retryAt[id] = DateTime.now().add(wait);
        Timer(wait + const Duration(milliseconds: 300), () {
          if (mounted) setState(() {});
        });
      }
    });
  }

  /// 확인하지 못한 기록을 다시 확인
  void _retryFailed() => setState(() {
        _fails.clear();
        _retryAt.clear();
      });

  List<MedRecord> get _unchecked =>
      [for (final r in _myRecords) if (r.drugs.isNotEmpty && !_fresh(r)) r];

  /// 첫 화면이 다 뜬 뒤에 자동 확인을 시작한다
  bool _autoReady = false;

  bool _fresh(MedRecord r) => r.last != null && r.last!.matches(r.drugs);

  List<MedRecord> get _pending => [
        for (final r in _myRecords)
          if (r.drugs.isNotEmpty && !_fresh(r) && !_gaveUp(r.id) && !_waiting(r.id)) r
      ];

  /// 동시에 확인하는 기록 수 (식약처 서버에 한꺼번에 너무 많이 묻지 않을 만큼)
  static const _autoParallel = 5;
  final Map<String, Timer> _autoTimers = {};

  List<Widget> _autoCheckers() {
    final person = _selected;
    final list = person == null || _selecting || !_autoReady
        ? const <MedRecord>[]
        : _pending.take(_autoParallel).toList();
    String keyOf(MedRecord r) => 'auto-${r.id}-${r.drugs.join('|')}';
    final keys = {for (final r in list) keyOf(r)};
    for (final k in _autoTimers.keys.where((k) => !keys.contains(k)).toList()) {
      _autoTimers.remove(k)?.cancel();
    }
    final out = <Widget>[];
    for (final r in list) {
      final key = keyOf(r);
      // 너무 오래 걸리면 이 기록은 건너뛴다 (기록을 열면 직접 확인할 수 있음)
      _autoTimers.putIfAbsent(
          key,
          () => Timer(const Duration(seconds: 90), () => _failed(r.id)));
      out.add(Positioned(
        left: 0,
        top: 0,
        child: Offstage(
          child: TickerMode(
            enabled: false,
            child: HeroMode(
              enabled: false,
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 360,
                  height: 640,
                  child: ResultScreen(
                    key: ValueKey(key),
                    child: person!,
                    names: List.of(r.drugs),
                    recordId: r.id,
                    asOf: r.createdAt,
                    letters: Map.of(r.safetyLetters),
                    onFinished: (snap) async {
                      r.last = snap;
                      // 확인 결과만 저장된 기록에 옮겨 적는다 (그사이 바뀐 다른 내용을 덮어쓰지 않도록)
                      await AppStorage.saveSnapshot(r.id, snap);
                      for (final x in _records.where((x) => x.id == r.id)) {
                        x.last = snap;
                      }
                      if (mounted) setState(() {});
                    },
                    onFailed: () {
                      _failed(r.id);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return out;
  }

  /// 기록 카드의 실손보험 청구 표시 (청구를 아직 안 한 것만)
  (String, Color, Color)? _claimChip(MedRecord r) {
    if (!kShowSilson24 || r.otc || !_silsonDone) return null;
    if (r.fullyClaimed && r.claimLevel != null) {
      return ('실손 청구 완료', AppColors.sub, const Color(0xFFF1F3F5));
    }
    return switch (r.claimLevel) {
      0 => ('실손24 서류 없이 바로 청구 가능', AppColors.primaryDark, AppColors.primarySoft),
      1 when !r.claimed => ('병원비만 서류 없이 청구 가능', const Color(0xFF9A3412), const Color(0xFFFFF4E8)),
      _ => null,
    };
  }

  /// 실손24 연계 여부를 뒤에서 한꺼번에 확인해 기록에 적는다 (청구 기한 3년 안, 아직 청구 안 한 것만).
  /// 확인이 다 끝난 뒤에 한 번에 보여준다 (하나씩 올라오면 헷갈리므로).
  bool _silsonRunning = false;
  bool _silsonDone = false;
  final Set<String> _silsonTried = {};

  bool _needsSilson(MedRecord r, DateTime cutoff) {
    if (r.otc || r.fullyClaimed || _silsonTried.contains(r.id)) return false;
    if (!r.createdAt.isAfter(cutoff) || r.hospitalName.isEmpty) return false;
    final needPharm = r.silsonH == 'on' && !r.inHouse && r.pharmacy.isNotEmpty && r.silsonP.isEmpty;
    return r.silsonH.isEmpty || needPharm;
  }

  Future<void> _runSilson() async {
    if (_silsonRunning || !kShowSilson24 || !_placesReady) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 365 * 3));
    final todo = [for (final r in _records) if (_needsSilson(r, cutoff)) r];
    if (todo.isEmpty) {
      if (!_silsonDone && mounted) setState(() => _silsonDone = true);
      return;
    }
    _silsonRunning = true;
    if (mounted) setState(() => _silsonDone = false);
    try {
      _silsonTried.addAll(todo.map((r) => r.id));
      final changed = await updateRecordsSilson(todo);
      await AppStorage.saveSilson(changed);
      // 그사이 목록을 다시 읽었으면 새 목록의 같은 기록에도 옮겨 적는다
      final byId = {for (final c in changed) c.id: c};
      for (final x in _records) {
        final c = byId[x.id];
        if (c != null) {
          x
            ..silsonH = c.silsonH
            ..silsonP = c.silsonP;
        }
      }
    } catch (_) {
    } finally {
      _silsonRunning = false;
      if (mounted) setState(() => _silsonDone = true);
    }
  }

  /// 기록 카드의 안전 확인 상태 표시
  (String, Color)? _statusOf(MedRecord r) {
    if (r.drugs.isEmpty) return null;
    if (!_fresh(r)) {
      return _gaveUp(r.id)
          ? ('확인 못함', AppColors.sub)
          : ('확인 중', AppColors.sub);
    }
    final s = r.last!;
    final p = _selected;
    final hard = s.mixPairs.isNotEmpty ||
        s.drugs.any((d) =>
            d.ageRule != null ||
            (d.preg && (p?.pregnant ?? false)) ||
            (d.allergy != null && (p?.allergies.isNotEmpty ?? false))) ||
        matchRecalls([r], _recalls).isNotEmpty;
    if (hard) return ('확인 필요', const Color(0xFFC62828));
    if (letterHits([r]).isNotEmpty) return ('주의 알림', const Color(0xFF9A3412));
    return ('문제없음', const Color(0xFF1E7B3A));
  }

  /// 기록의 안전 확인 결과 화면을 바로 연다 (기록 화면을 거치지 않음). 결과는 기록에 저장.
  Future<void> _openResult(BuildContext ctx, MedRecord r) async {
    final person = _selected;
    if (person == null) return;
    await Navigator.push(
      ctx,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          child: person,
          record: r,
          names: List.of(r.drugs),
          recordId: r.id,
          asOf: r.createdAt,
          letters: Map.of(r.safetyLetters),
          recalls: {for (final h in matchRecalls([r], _recalls)) h.drug: h},
          onSnapshot: (snap) {
            r.last = snap;
            AppStorage.saveRecord(r);
          },
        ),
      ),
    );
    await _load();
  }

  /// 기록을 만드는 두 가지 길: 직접 입력 / 심평원 1년 기록 불러오기
  Widget _addRow() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.add_rounded,
              title: '직접 추가',
              filled: true,
              onTap: _newRecord,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionCard(
              icon: Icons.download_rounded,
              title: '1년 기록 불러오기',
              onTap: _openImport,
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 8, left: 2),
          child: KText(
              '지난 1년 처방 기록을 심평원 투약이력 파일로 한 번에 불러올 수 있어요.',
              flow: true,
              style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.45)),
        ),
      ]);

  /// 기록을 모아 보는 화면들: 목록 바로 위에 얇게 나란히
  Widget _viewsRow() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(
            child: _SlimButton(
              icon: Icons.insights_outlined,
              tint: kPastelTeal,
              label: '복용 리포트',
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ReportScreen(person: _selected!))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SlimButton(
              icon: Icons.edit_note,
              tint: kPastelLavender,
              label: '반응 기록',
              badge: _reactionCount[_selectedId] ?? 0,
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ReactionListScreen(person: _selected!)));
                await _load();
              },
            ),
          ),
        ]),
      );

  Widget _notice() => const SourcesNote();
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
    final (pBg, pFg) = pastelFor(child.id);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.line,
              width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: pBg,
              child: KText(
                child.name.isEmpty ? '?' : child.name.characters.first,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: pFg),
              ),
            ),
            if (selected)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.check, size: 11, color: Colors.white),
                ),
              ),
          ]),
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
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                KText(child.ageLabel,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.sub)),
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
            Icon(Icons.person_add_alt_1_outlined, color: AppColors.sub),
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
    this.status,
    this.claim,
    this.selecting = false,
    this.selected = false,
  });

  final MedRecord record;

  /// 안전 확인 상태 (글자, 색)
  final (String, Color)? status;

  /// 실손보험 청구 상태 (글자, 글자색, 배경색)
  final (String, Color, Color)? claim;
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
                  color: selected ? AppColors.primaryDark : AppColors.sub,
                  size: 26,
                ),
              )
            else
              Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: record.otc ? kOtcBg : AppColors.brandTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                      record.otc ? Icons.storefront_outlined : Icons.medication_outlined,
                      color: record.otc ? kOtcFg : AppColors.brand),
                ),
                const SizedBox(height: 3),
                Text(record.otc ? '일반' : '처방',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: record.otc ? kOtcFg : AppColors.brand)),
              ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: KText(record.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.ink)),
                    ),
                    const SizedBox(width: 6),
                    // 어디서 온 기록인지
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F4F3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(record.imported ? '심평원 불러옴' : '직접 입력',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.sub,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    Flexible(
                      child: KText(
                        names.isEmpty
                            ? '${formatDate(record.createdAt)} · 약 없음'
                            : '${formatDate(record.createdAt)} · 약 ${names.length}개',
                        maxLines: 1,
                        style: const TextStyle(fontSize: 13, color: AppColors.sub),
                      ),
                    ),
                    if (status case (final label, final color)) ...[
                      const SizedBox(width: 8),
                      Icon(
                          switch (label) {
                            '문제없음' => Icons.check_circle,
                            '확인 필요' => Icons.error,
                            '주의 알림' => Icons.info,
                            _ => Icons.hourglass_top_rounded,
                          },
                          size: 14,
                          color: color),
                      const SizedBox(width: 3),
                      Text(label,
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                    ],
                  ]),
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
                  if (claim case (final label, final fg, final bg)) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration:
                          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.receipt_long_rounded, size: 14, color: fg),
                        const SizedBox(width: 4),
                        Text(label,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
                      ]),
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
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: [
        Icon(icon, size: 40,
            color: onTap != null ? AppColors.primary : const Color(0xFFB0B8C1)),
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

/// 약국 구입약(일반의약품) 색
const kOtcFg = Color(0xFFD06A2E);
const kOtcBg = Color(0xFFFCEEE4);

class _KindOption extends StatelessWidget {
  const _KindOption({required this.otc, required this.title, required this.sub, required this.onTap});

  final bool otc;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: otc ? kOtcBg : AppColors.brandTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(otc ? Icons.storefront_outlined : Icons.medication_outlined,
                  color: otc ? kOtcFg : AppColors.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                KText(title,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                KText(sub, style: const TextStyle(fontSize: 13, color: AppColors.sub)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.sub),
          ]),
        ),
      ),
    );
  }
}
class _ActionCard extends StatelessWidget {
  const _ActionCard(
      {required this.icon, required this.title, required this.onTap, this.filled = false});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onPrimary : AppColors.primaryDark;
    return Material(
      color: filled ? AppColors.primary : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: filled ? BorderSide.none : const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: KText(title,
                  maxLines: 1,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: fg)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SlimButton extends StatelessWidget {
  const _SlimButton(
      {required this.icon, required this.tint, required this.label, required this.onTap, this.badge = 0});
  final IconData icon;
  final (Color, Color) tint;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: tint.$2),
              const SizedBox(width: 6),
              Flexible(
                child: KText(label,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: kNoteBg, borderRadius: BorderRadius.circular(10)),
                  child: Text('$badge',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700, color: kNoteFg)),
                ),
              ],
            ]),
          ),
        ),
      );
}
