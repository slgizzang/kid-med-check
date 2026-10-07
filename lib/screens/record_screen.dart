import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/models.dart';
import '../logic/reaction.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';
import '../ui/dashboard.dart';
import '../ui/place_sheet.dart';
import '../ui/reaction_sheet.dart';
import 'confirm_screen.dart';
import 'result_screen.dart';

/// 처방 기록 하나. 약을 찍거나 입력해서 모아두고, 언제든 다시 열어 확인한다.
/// 모든 변경은 바로 저장되므로 뒤로 가도 사라지지 않는다.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.child, required this.record});

  final ChildProfile child;
  final MedRecord record;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final MedRecord _r = widget.record;
  bool _busy = false;

  Future<void> _save() => AppStorage.saveRecord(_r);

  /// 마지막으로 확인한 결과 (앱이 켜져 있는 동안). 약 목록·복용자 정보가 같으면 다시 조회하지 않는다.
  static final Map<String, (String, List<DrugCheck>)> _resultCache = {};

  String get _signature {
    final c = widget.child;
    return [
      ..._r.drugs,
      '#${c.birthDate.toIso8601String()}',
      '${c.ageInMonths(_r.createdAt)}',
      '${c.pregnant}',
      '${c.nursing}',
      ...c.allergies,
    ].join('|');
  }

  /// 지난 결과가 지금 목록·정보와 같은지
  bool get _fresh =>
      _r.last != null &&
      _r.last!.matches(_r.drugs) &&
      _r.last!.pregnant == widget.child.pregnant &&
      _r.last!.nursing == widget.child.nursing &&
      _r.last!.allergies.join('|') == widget.child.allergies.join('|');

  List<ReactionNote> _notes = const [];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    _notes = await AppStorage.reactions(widget.child.id);
    if (mounted) setState(() {});
  }

  /// 목록의 이름을 지난 확인 결과의 확정된 제품명·성분으로 (있으면)
  (String, String) _resolved(String name) {
    for (final d in _r.last?.drugs ?? const []) {
      if (d.query == name && !d.needsPick) return (d.title, d.ingredient);
    }
    return (name, '');
  }

  /// 여러 약을 함께 먹어 어떤 약 때문인지 모를 때: 처방 전체에 기록
  Future<void> _addGroupReaction() async {
    final items = [for (final d in _r.drugs) _resolved(d)];
    final n = await showReactionSheet(context,
        childId: widget.child.id,
        drug: _r.title,
        recordId: _r.id,
        items: items);
    if (n != null) {
      await _loadNotes();
      _snack('반응을 기록했어요. 이 중 어떤 약이라도 다시 처방되면 알려드릴게요.');
    }
  }

  Future<void> _addReaction(String name) async {
    final (drug, ingr) = _resolved(name);
    final n = await showReactionSheet(context,
        childId: widget.child.id, drug: drug, ingredient: ingr, recordId: _r.id);
    if (n != null) {
      await _loadNotes();
      _snack('반응을 기록했어요. 같은 약이나 같은 성분이 다시 처방되면 알려드릴게요.');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: KText(msg)));

  void _addNames(Iterable<String> names) {
    var added = 0;
    setState(() {
      for (final raw in names) {
        final n = DrugNameExtractor.toSearchName(raw);
        if (n.length >= 2 && !DrugNameExtractor.isFormOnly(n) && !_r.drugs.contains(n)) {
          _r.drugs.add(n);
          added++;
        }
      }
    });
    _save();
    if (added > 0) _snack('$added개 약을 기록에 추가했어요.');
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _r.title);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const KText('기록 이름'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 소아과 감기약'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const KText('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const KText('저장')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      setState(() => _r.title = v);
      _save();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const KText('이 기록을 삭제할까요?'),
        content: const KText('기록에 담긴 약 목록도 함께 지워져요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const KText('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const KText('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    await AppStorage.deleteRecord(_r.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _manualAdd() async {
    final c = TextEditingController();
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KText('약 이름 직접 입력',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const KText('여러 개는 쉼표나 줄바꿈으로 구분하세요.',
                style: TextStyle(color: AppColors.sub)),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '예: 세토펜현탁액, 코푸시럽',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const KText('추가'),
            ),
          ],
        ),
      ),
    );
    if (v != null) _addNames(DrugNameExtractor.splitManual(v));
  }

  Future<void> _scan(ImageSource source) async {
    final XFile? file;
    try {
      file = await ImagePicker()
          .pickImage(source: source, maxWidth: 3200, imageQuality: 95);
    } catch (e) {
      _snack('사진을 가져오지 못했어요.');
      return;
    }
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    String text = '';
    String? error;
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(file.path));
      text = result.text;
    } catch (e) {
      error = '$e';
    } finally {
      await recognizer.close();
    }
    if (!mounted) return;
    setState(() => _busy = false);


    if (error != null) {
      debugPrint('OCR error: $error');
      _snack('사진에서 글자를 읽지 못했어요. 직접 입력해주세요.');
      return;
    }
    final picked = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmScreen(
          child: widget.child,
          initialNames: DrugNameExtractor.extract(text),
          rawText: text,
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty) _addNames(picked);
  }

  /// 병원 이름: 고른 것, 없으면 기록 제목에서 ("9월 21일 써니이비인후과의원" → "써니이비인후과의원")
  String get _place {
    if (_r.hospital.trim().isNotEmpty) return _r.hospital.trim();
    final t = _r.title
        .replaceFirst(RegExp(r'^\s*\d{1,2}월\s*\d{1,2}일\s*'), '')
        .replaceAll(RegExp(r'^(처방|약국 구입)$'), '')
        .trim();
    return RegExp(r'(의원|병원|센터|클리닉|보건소)').hasMatch(t) ? t : '';
  }

  /// 병원·약국 검색해서 고르기
  Future<bool> _pickPlace({required bool pharmacy}) async {
    final hit = await showPlaceSheet(context,
        pharmacy: pharmacy, initial: pharmacy ? _r.pharmacy : _place);
    if (hit == null || hit.name.trim().isEmpty) return false;
    setState(() {
      if (pharmacy) {
        _r.pharmacy = hit.name.trim();
        _r.pharmacyAddr = hit.addr;
      } else {
        _r.hospital = hit.name.trim();
        _r.hospitalAddr = hit.addr;
      }
    });
    _save();
    return true;
  }

  /// 주소 앞부분(시·구)만: "서울특별시 강남구 테헤란로 1" → "서울특별시 강남구"
  static String _region(String addr) =>
      addr.trim().split(RegExp(r'\s+')).take(2).join(' ');

  /// 네이버 지도에서 병원(또는 약국)을 연다. 실손24 연계 기관이면 상세 화면의 배너·"청구 바로가기"로
  /// 네이버 안에서 청구를 끝낼 수 있다 (2026.10.7~). 지도 앱이 없으면 웹 지도로.
  Future<void> _claimOnNaverMap({required bool pharmacy}) async {
    var name = pharmacy ? _r.pharmacy : _place;
    if (name.isEmpty) {
      if (!await _pickPlace(pharmacy: pharmacy)) return;
      name = pharmacy ? _r.pharmacy : _place;
    }
    final region = _region(pharmacy ? _r.pharmacyAddr : _r.hospitalAddr);
    final enc = Uri.encodeComponent(region.isEmpty ? name : '$region $name');
    var ok = false;
    try {
      ok = await launchUrl(
          Uri.parse('nmap://search?query=$enc&appname=com.kidmedcheck.kid_med_check'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      await launchUrl(Uri.parse('https://map.naver.com/p/search/$enc'),
          mode: LaunchMode.externalApplication);
    }
  }

  /// 보험개발원 실손24 (참여 병원·약국이면 서류 없이 청구)
  Future<void> _openSilson24() async {
    await launchUrl(Uri.parse('https://www.silson24.or.kr'), mode: LaunchMode.externalApplication);
  }

  /// 실손보험 청구 카드: 병원비(병원)와 약값(약국)을 각각 청구
  Widget _claimCard() {
    const small = TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: KText('실손보험 청구',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          if (_r.fullyClaimed) const _DoneChip('모두 청구 완료'),
        ]),
        const SizedBox(height: 4),
        const KText('네이버 지도에서 실손24로 바로 청구해요.', style: small),
        const SizedBox(height: 12),
        _ClaimPart(
          pharmacy: false,
          name: _place,
          addr: _r.hospitalAddr,
          done: _r.claimed,
          onPick: () => _pickPlace(pharmacy: false),
          onClaim: () => _claimOnNaverMap(pharmacy: false),
          onDone: (v) {
            setState(() => _r.claimed = v);
            _save();
          },
        ),
        const SizedBox(height: 10),
        _ClaimPart(
          pharmacy: true,
          name: _r.pharmacy,
          addr: _r.pharmacyAddr,
          done: _r.claimedPharm,
          onPick: () => _pickPlace(pharmacy: true),
          onClaim: () => _claimOnNaverMap(pharmacy: true),
          onDone: (v) {
            setState(() => _r.claimedPharm = v);
            _save();
          },
        ),
        const SizedBox(height: 12),
        const KText(
          '지도에서 병원·약국 화면을 열고 실손24 배너의 "청구 바로가기"를 누르면 네이버 안에서 청구가 끝나요. '
          '마이데이터에 동의하면 진료일·보험사·계좌를 따로 입력하지 않아도 돼요.',
          style: small,
        ),
        const SizedBox(height: 4),
        const KText(
          '배너가 없으면 아직 실손24에 연계되지 않은 곳이에요. 이때는 서류를 받아 보험사 앱으로 청구해야 해요.',
          style: small,
        ),
        Wrap(spacing: 4, children: [
          TextButton(
            onPressed: _openSilson24,
            child: const KText('실손24 홈페이지', maxLines: 1),
          ),
          TextButton(
            onPressed: () => launchUrl(
                Uri.parse('https://www.silson24.or.kr/claim/web/serviceHospitalList'),
                mode: LaunchMode.externalApplication),
            child: const KText('참여기관 목록', maxLines: 1),
          ),
        ]),
      ]),
    );
  }

  Future<void> _check() async {
    if (_r.drugs.isEmpty) {
      _snack('먼저 약을 추가해주세요.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          child: widget.child,
          names: List.of(_r.drugs),
          recordId: _r.id,
          asOf: _r.createdAt,
          reuse: _resultCache[_r.id]?.$1 == _signature ? _resultCache[_r.id]!.$2 : null,
          onChecks: (checks) => _resultCache[_r.id] = (_signature, checks),
          onSnapshot: (snap) {
            _r.last = snap;
            _save();
          },
          onReplace: (oldName, newName) {
            final i = _r.drugs.indexOf(oldName);
            if (i >= 0) {
              if (_r.drugs.contains(newName)) {
                _r.drugs.removeAt(i);
              } else {
                _r.drugs[i] = newName;
              }
              _save();
            }
          },
        ),
      ),
    );
    await _loadNotes();
  }

  Widget? _noteLine(String name) {
    final (drug, ingr) = _resolved(name);
    // 이 기록에서 적은 반응을 먼저, 없으면 이 기록 날짜 이전에 적은 지난 반응
    final hits = reactionsFor(_notes, drug, ingr,
        recordId: _r.id, before: _r.createdAt, includeOwn: true);
    if (hits.isEmpty) return null;
    final own = hits.where((h) => h.$1.recordId == _r.id).toList();
    final (n, m) = own.isNotEmpty ? own.first : hits.first;
    final label = own.isNotEmpty ? '이번 반응' : '지난 반응';
    return KText('$label · ${reactionLine(n, m)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: kNoteFg, fontWeight: FontWeight.w600));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _rename,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: KText(_r.title, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined, size: 18, color: AppColors.sub),
          ]),
        ),
        actions: [
          IconButton(
              tooltip: '기록 삭제',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
            children: [
              KText(
                '${_r.otc ? '약국 구입' : '처방'} · ${widget.child.name} · ${_r.otc ? '구입일' : '처방일'} 기준 ${formatAge(widget.child.ageInMonths(_r.createdAt))} · ${formatDate(_r.createdAt)}',
                style: const TextStyle(color: AppColors.sub),
              ),
              const SizedBox(height: 18),
              if (_r.last != null) ...[
                const SizedBox(height: 4),
                const SectionTitle('지난 확인 결과'),
                if (!_fresh)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(children: [
                      Icon(Icons.refresh, size: 18, color: Color(0xFFB45309)),
                      SizedBox(width: 8),
                      Expanded(
                        child: KText('약 목록이나 정보가 바뀌었어요. 아래 "약 안전 확인"을 다시 눌러주세요.',
                            style: TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                ResultDashboard(
                  snap: _r.last!,
                  person: widget.child,
                  showDate: true,
                  stale: !_fresh,
                ),
              ],
              const SizedBox(height: 26),
              SectionTitle('약 목록',
                  trailing: KText('${_r.drugs.length}개',
                      style: const TextStyle(color: AppColors.sub))),
              if (_r.drugs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const KText(
                    '먹는 약을 입력해주세요.\n아래의 촬영·사진첩·직접 입력 중 편한 방법을 쓰면 되고, 입력한 약은 자동으로 저장돼요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.sub, height: 1.5),
                  ),
                )
              else
                Card(
                  child: Column(children: [
                    for (var i = 0; i < _r.drugs.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 60),
                      ListTile(
                        leading: const CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.mint,
                          child: Icon(Icons.medication_liquid_outlined,
                              size: 20, color: AppColors.primaryDark),
                        ),
                        title: KText(_r.drugs[i],
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: _noteLine(_r.drugs[i]),
                        onTap: () => _addReaction(_r.drugs[i]),
                        contentPadding: const EdgeInsets.only(left: 14, right: 2),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          // 누를 수 있다는 걸 보이도록 버튼 모양으로
                          Material(
                            color: kNoteBg,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _addReaction(_r.drugs[i]),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.edit_note, size: 18, color: kNoteFg),
                                  SizedBox(width: 4),
                                  Text('반응 기록',
                                      style: TextStyle(
                                          color: kNoteFg,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                ]),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '빼기',
                            icon: const Icon(Icons.close, size: 20, color: AppColors.sub),
                            onPressed: () {
                              setState(() => _r.drugs.removeAt(i));
                              _save();
                            },
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
              if (_r.drugs.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8, left: 4),
                  child: KText('약을 먹고 설사·발진 같은 반응이 있었다면 "반응 기록"을 눌러 적어두세요.',
                      style: TextStyle(fontSize: 12, color: AppColors.sub)),
                ),
              if (_r.drugs.length >= 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addGroupReaction,
                    icon: const Icon(Icons.edit_note, size: 20),
                    label: const KText('어떤 약 때문인지 모르겠다면: 처방 전체에 반응 기록'),
                  ),
                ),
              const SizedBox(height: 20),
              const SectionTitle('약 추가하기'),
              Row(children: [
                Expanded(
                  child: _AddTile(
                    icon: Icons.photo_camera_outlined,
                    label: '촬영',
                    onTap: () => _scan(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AddTile(
                    icon: Icons.photo_library_outlined,
                    label: '사진첩',
                    onTap: () => _scan(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AddTile(
                    icon: Icons.keyboard_outlined,
                    label: '직접 입력',
                    onTap: _manualAdd,
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              const KText(
                '촬영·사진첩은 사진 속 글자를 읽어(OCR) 식약처 약 목록과 맞는 이름만 골라요. '
                '처방전·약봉지를 통째로 찍어도 돼요.',
                style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5),
              ),
              const SizedBox(height: 20),
              // 병원 처방 기록이면 실손보험 청구: 네이버 지도의 실손24 연계로 바로 청구
              if (kShowSilson24 && !_r.otc) _claimCard(),
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 18),
                    KText('글자를 읽는 중…'),
                  ]),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: _r.drugs.isEmpty ? null : _check,
            icon: const Icon(Icons.verified_user_outlined),
            label: KText(_fresh
                ? '안전 확인 결과 자세히 보기'
                : widget.child.ageInMonths(_r.createdAt) >= 19 * 12
                    ? '약 ${_r.drugs.length}개 안전 확인'
                    : '우리 아이 약 ${_r.drugs.length}개 안전 확인'),
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.primary : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: primary ? null : Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: primary ? AppColors.onPrimary : AppColors.primaryDark),
              const SizedBox(height: 4),
              KText(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: primary ? AppColors.onPrimary : AppColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneChip extends StatelessWidget {
  const _DoneChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
      );
}

/// 청구 한 건 (병원비 또는 약값): 기관 이름 + 청구 버튼 + 완료 표시
class _ClaimPart extends StatelessWidget {
  const _ClaimPart({
    required this.pharmacy,
    required this.name,
    required this.addr,
    required this.done,
    required this.onPick,
    required this.onClaim,
    required this.onDone,
  });

  final bool pharmacy;
  final String name;
  final String addr;
  final bool done;
  final VoidCallback onPick;
  final VoidCallback onClaim;
  final ValueChanged<bool> onDone;

  @override
  Widget build(BuildContext context) {
    final (tBg, tFg) = pharmacy ? kPastelSky : kPastelTeal;
    final label = pharmacy ? '약값' : '병원비';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPick,
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: tBg, borderRadius: BorderRadius.circular(11)),
              child: Icon(
                  pharmacy ? Icons.local_pharmacy_outlined : Icons.local_hospital_outlined,
                  color: tFg,
                  size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$label · ${pharmacy ? '약국' : '병원'}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.sub, fontWeight: FontWeight.w600)),
                KText(name.isEmpty ? (pharmacy ? '약국 검색해서 입력' : '병원 검색해서 입력') : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        color: name.isEmpty ? AppColors.sub : AppColors.ink,
                        fontWeight: name.isEmpty ? FontWeight.w500 : FontWeight.w700)),
                if (addr.isNotEmpty)
                  KText(addr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.sub)),
              ]),
            ),
            KText(name.isEmpty ? '검색' : '변경',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: done ? Colors.white : AppColors.primary,
                  foregroundColor: done ? AppColors.primaryDark : AppColors.onPrimary,
                  side: done ? const BorderSide(color: AppColors.line) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onClaim,
                child: KText(done ? '$label 다시 열기' : '$label 청구하기',
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onDone(!done),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 22, color: done ? AppColors.primary : AppColors.sub),
                const SizedBox(width: 4),
                Text('완료',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: done ? AppColors.primaryDark : AppColors.sub)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}
