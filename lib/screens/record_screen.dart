import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/models.dart';
import '../logic/place_resolver.dart';
import '../logic/silson24.dart';
import '../logic/dur_api.dart';
import '../logic/reaction.dart';
import '../logic/recall.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';
import '../ui/dashboard.dart';
import '../ui/place_sheet.dart';
import '../ui/record_header.dart';
import '../ui/reaction_sheet.dart';
import 'confirm_screen.dart';
import 'result_screen.dart';

/// 처방 기록 하나. 약을 찍거나 입력해서 모아두고, 언제든 다시 열어 확인한다.
/// 모든 변경은 바로 저장되므로 뒤로 가도 사라지지 않는다.
class RecordScreen extends StatefulWidget {
  const RecordScreen(
      {super.key, required this.child, required this.record, this.focusClaim = false});

  final ChildProfile child;
  final MedRecord record;

  /// 열자마자 실손보험 청구 카드로 스크롤 (리포트의 미청구 목록에서 들어올 때)
  final bool focusClaim;

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
    _loadRecalls();
    if (kShowSilson24 && !_r.otc) _checkBoth();
    if (widget.focusClaim) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _claimKey.currentContext;
        if (c != null) {
          Scrollable.ensureVisible(c,
              duration: const Duration(milliseconds: 350), alignment: 0.1);
        }
      });
    }
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

  /// 병원 이름: 고른 것, 없으면 기록 제목에서
  String get _place => _r.hospitalName;

  /// 병원·약국 검색해서 고르기
  Future<bool> _pickPlace({required bool pharmacy}) async {
    final before = pharmacy ? _r.pharmacy : _place;
    final hit = await showPlaceSheet(context, pharmacy: pharmacy, initial: before);
    if (hit == null || hit.name.trim().isEmpty) return false;
    setState(() {
      if (pharmacy) {
        _r.pharmacy = hit.name.trim();
        _r.pharmacyAddr = hit.addr;
        _r.pharmacyCode = hit.code;
        _r.pharmacyPos = hit.lat != null && hit.lng != null ? (hit.lat!, hit.lng!) : null;
      } else {
        _r.hospital = hit.name.trim();
        _r.hospitalAddr = hit.addr;
        _r.hospitalCode = hit.code;
        _r.hospitalPos = hit.lat != null && hit.lng != null ? (hit.lat!, hit.lng!) : null;
      }
    });
    await AppStorage.saveRecord(_r);
    // 같은 이름의 다른 기록(아직 어느 곳인지 모르는 것)에도 이 선택을 적용
    if (hit.lat != null && before.isNotEmpty) {
      await AppStorage.applyPlace(widget.child.id, before, pharmacy: pharmacy, hit: hit);
    }
    if (pharmacy) {
      _checkSilson(pharmacy: true);
    } else {
      _checkBoth();
    }
    return true;
  }

  /// 실손24 연계 여부 (false = 병원, true = 약국). null이면 아직 확인 안 함.
  final Map<bool, SilsonCheck?> _silson = {false: null, true: null};
  final Set<bool> _silsonLoading = {};

  /// 병원 → 약국 순서로 확인 (약국은 병원 근처를 기준으로 고르므로)
  Future<void> _checkBoth() async {
    setState(() => _silsonLoading.addAll({false, true}));
    await _resolvePair();
    await Future.wait([_checkSilson(pharmacy: false), _checkSilson(pharmacy: true)]);
  }

  /// 이름만 있는 병원·약국의 위치·주소·코드를 심평원 정보로 채운다.
  /// 같은 이름이 여럿이면 "서로 가장 가까운 병원·약국 짝"을 고른다 (처방 병원 옆 약국).
  Future<void> _resolvePair() async {
    try {
      final api = DurApi(await AppStorage.apiKey());
      final n = await fillPlaces(api, [_r]);
      if (n > 0 && mounted) {
        setState(() {});
        await _save();
      }
    } catch (_) {}
  }

  /// 병원·약국이 실손24로 서류 없이 청구 가능한지 확인 (이름이 있을 때만)
  Future<void> _checkSilson({required bool pharmacy}) async {
    final name = pharmacy ? _r.pharmacy : _place;
    if (name.isEmpty) {
      setState(() => _silson[pharmacy] = null);
      return;
    }
    setState(() => _silsonLoading.add(pharmacy));
    final c = await Silson24().check(name,
        pharmacy: pharmacy,
        addr: pharmacy ? _r.pharmacyAddr : _r.hospitalAddr,
        code: pharmacy ? _r.pharmacyCode : _r.hospitalCode,
        // 위치는 심평원 자료로 정확히 정해진 경우에만 넘긴다 (내 위치로 추측하지 않음).
        // 자기 위치를 모르면 짝 기관 위치 주변 1km 안에서만 맞춘다.
        at: pharmacy ? _r.pharmacyPos : _r.hospitalPos,
        near: pharmacy ? _r.hospitalPos : _r.pharmacyPos);
    if (!mounted) return;
    setState(() {
      _silsonLoading.remove(pharmacy);
      _silson[pharmacy] = c;
      // 메인 화면 기록 카드·요약에서도 바로 보이도록 기록에 적어 둔다
      final code = silsonStateCode(c.state);
      if (code.isNotEmpty) {
        if (pharmacy) {
          _r.silsonP = code;
        } else {
          _r.silsonH = code;
        }
      }
      // 실손24에서 확실히 찾은 곳의 위치를 기억해 두면 다음부터는 바로 그곳으로 맞춘다
      if (c.state != SilsonState.unknown && c.lat != null && c.lng != null) {
        if (pharmacy) {
          _r.pharmacyPos ??= (c.lat!, c.lng!);
        } else {
          _r.hospitalPos ??= (c.lat!, c.lng!);
        }
      }
      // 실손24에서 확실히 찾았는데 주소가 비어 있으면 채워 둔다
      if (c.addr.isNotEmpty) {
        if (pharmacy && _r.pharmacyAddr.isEmpty) _r.pharmacyAddr = c.addr;
        if (!pharmacy && _r.hospitalAddr.isEmpty) _r.hospitalAddr = c.addr;
      }
    });
    _save();
  }

  /// 실손24로 청구: 기관 이름이 없으면 먼저 고르고, 실손24를 연다.
  Future<void> _claimOnSilson24({required bool pharmacy}) async {
    if ((pharmacy ? _r.pharmacy : _place).isEmpty) {
      if (!await _pickPlace(pharmacy: pharmacy)) return;
      await _checkSilson(pharmacy: pharmacy);
      if (_silson[pharmacy]?.state == SilsonState.notEnabled) return;
    }
    await _openSilson24();
  }

  /// 보험개발원 실손24 (참여 병원·약국이면 서류 없이 청구)
  Future<void> _openSilson24() async {
    await launchUrl(Uri.parse('https://www.silson24.or.kr'), mode: LaunchMode.externalApplication);
  }

  final _claimKey = GlobalKey();

  /// 실손보험 청구 카드: 병원비(병원)와 약값(약국)을 각각 청구
  /// 병원·약국 실손24 연계 조합에 따라 지금 어떻게 청구하면 되는지
  /// 병원·약국 실손24 연계 조합에 따라 결론 한 줄 + 할 일 한 줄.
  /// 핵심: 서류 없이 청구되는지는 '병원' 연계가 정한다. 약국만 연계면 결국 병원 서류가 필요해 미연계와 같다.
  Widget _claimGuide(TextStyle small) {
    final checking = _silsonLoading.isNotEmpty;
    final h = _silson[false]?.state;
    final noPharm = _r.inHouse || _r.pharmacy.isEmpty;
    final p = noPharm ? null : _silson[true]?.state;
    const on = SilsonState.enabled, off = SilsonState.notEnabled;
    const docs = '진료비 영수증·세부내역서·처방전을 받아 보험사 앱으로 청구하세요.';
    // (제목, 설명, 단계: 0 좋음 / 1 일부 / 2 서류 필요)
    final (String, String, int)? g = checking || _place.isEmpty
        ? null
        : h == on && (noPharm || p == on)
            ? (
                '서류 없이 바로 청구 가능',
                noPharm ? '실손24에서 바로 청구하세요${_r.inHouse ? ' (약값 포함)' : ''}.' : '실손24에서 병원비·약값을 한 번에 청구하세요.',
                0
              )
            : h == on && p == off
                ? ('병원비만 서류 없이 청구 가능', '약국은 실손24 미연계예요. 약값은 약국 영수증과 처방전(환자 보관용)을 받아 보험사 앱으로 청구하세요.', 1)
                : h == on
                    ? ('병원비는 서류 없이 청구 가능', '약국은 연계 여부를 아직 확인하지 못했어요.', 1)
                    : h == off
                        ? (
                            '서류 준비 필요',
                            noPharm
                                ? '실손24 미연계 병원이에요. $docs'
                                : p == on
                                    ? '약국만 실손24에 연계돼 있어 병원 서류가 필요해요. 진료비 영수증·세부내역서·처방전을 받아 실손24 또는 보험사 앱으로 청구하세요.'
                                    : p == off
                                        ? '병원·약국 모두 실손24 미연계예요. $docs'
                                        : '실손24 미연계 병원이에요. $docs',
                            2
                          )
                        : null;
    if (g == null) {
      return KText('병원이 실손24에 연계돼 있으면 서류 없이 바로 청구할 수 있어요.', flow: true, style: small);
    }
    final (title, sub, level) = g;
    final (Color bg, Color fg, IconData icon) = switch (level) {
      0 => (AppColors.primarySoft, AppColors.primaryDark, Icons.check_circle_rounded),
      1 => (const Color(0xFFFFF4E8), const Color(0xFF9A3412), Icons.adjust_rounded),
      _ => (const Color(0xFFF1F3F5), const Color(0xFF374151), Icons.description_outlined),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 22, color: fg),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KText(title, style: TextStyle(fontSize: 15.5, color: fg, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            KText(sub, flow: true, style: TextStyle(fontSize: 13, color: fg, height: 1.45)),
          ]),
        ),
      ]),
    );
  }

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
          const KText('실손보험 청구',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
          IconButton(
            tooltip: '실손24 청구 방법',
            visualDensity: VisualDensity.compact,
            onPressed: () => _showClaimHelp(context),
            icon: const Icon(Icons.help_outline_rounded, size: 20, color: AppColors.sub),
          ),
          const Spacer(),
          if (_r.fullyClaimed) const _DoneChip('모두 청구 완료'),
        ]),
        const SizedBox(height: 4),
        _claimGuide(small),
        const SizedBox(height: 12),
        _ClaimPart(
          pharmacy: false,
          name: _place,
          addr: _r.hospitalAddr,
          done: _r.claimed,
          silson: _silson[false],
          checking: _silsonLoading.contains(false),
          onPick: () => _pickPlace(pharmacy: false),
          onClaim: () => _claimOnSilson24(pharmacy: false),
          onDone: (v) {
            setState(() => _r.claimed = v);
            _save();
          },
        ),
        const SizedBox(height: 10),
        if (_r.inHouse)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [
              Icon(Icons.local_pharmacy_outlined, size: 20, color: AppColors.sub),
              SizedBox(width: 10),
              Expanded(
                child: KText('약은 병원에서 바로 받았어요(원내 조제). 약값은 병원비 청구에 함께 들어가요.',
                    flow: true, style: TextStyle(fontSize: 13, color: AppColors.ink, height: 1.45)),
              ),
            ]),
          )
        else
        _ClaimPart(
          pharmacy: true,
          name: _r.pharmacy,
          addr: _r.pharmacyAddr,
          done: _r.claimedPharm,
          silson: _silson[true],
          checking: _silsonLoading.contains(true),
          // 병원이 미연계면 약값만 따로 청구할 때 서류를 직접 올려야 한다
          docsNeeded: _silson[false]?.state == SilsonState.notEnabled,
          onPick: () => _pickPlace(pharmacy: true),
          onClaim: () => _claimOnSilson24(pharmacy: true),
          onDone: (v) {
            setState(() => _r.claimedPharm = v);
            _save();
          },
        ),
        const SizedBox(height: 12),
        const KText('실손24 로그인 → "나의 실손청구"에서 진료 내역을 고르면 보험사로 바로 전송돼요.',
            flow: true, style: small),
        const SizedBox(height: 10),
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
          record: _r,
          names: List.of(_r.drugs),
          recordId: _r.id,
          asOf: _r.createdAt,
          letters: Map.of(_r.safetyLetters),
          recalls: {for (final h in _recallHits) h.drug: h},
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

  /// 이 기록의 약 중 식약처 회수 목록에 오른 것
  List<RecallHit> _recallHits = const [];

  Future<void> _loadRecalls() async {
    final list = await RecallStore.load(await AppStorage.apiKey());
    if (!mounted) return;
    setState(() => _recallHits = matchRecalls([_r], list));
  }

  /// 안전성 서한 표시와 반응 기록 줄
  Widget? _drugSub(String name) {
    // 회수·주의 알림 표시는 안전 확인을 한 뒤에만 (확인 결과와 함께 보이도록)
    final checked = _r.last != null && _fresh;
    final hit = checked ? _recallHits.where((h) => h.drug == name).firstOrNull : null;
    if (hit != null) {
      final note = _noteLine(name);
      final r = KText(hit.injected ? '회수된 주사' : '회수된 약',
          maxLines: 1,
          style: TextStyle(
              fontSize: 12,
              color: hit.injected ? const Color(0xFF334155) : const Color(0xFFB71C1C),
              fontWeight: FontWeight.w800));
      return note == null
          ? r
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [r, note]);
    }
    final note = _noteLine(name);
    if (!checked || !_r.safetyLetters.containsKey(name)) return note;
    const letter = KText('식약처 주의 알림 있음',
        maxLines: 1,
        style: TextStyle(fontSize: 12, color: Color(0xFF9A3412), fontWeight: FontWeight.w700));
    if (note == null) return letter;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [letter, note]);
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

  /// 기록 화면 맨 위: 초록 띠 위에 이 기록이 무엇인지 (누구 · 언제 · 어디)
  Widget _recordHeader() => RecordHeader(record: _r, person: widget.child);

  @override
  Widget build(BuildContext context) {
    // 메인 화면과 헷갈리지 않도록 기록 화면은 위쪽을 초록 띠로 (처방전 한 장을 연 느낌)
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        surfaceTintColor: Colors.transparent,
        title: KText('복용 기록',
            maxLines: 1,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
        actions: [
          IconButton(
              tooltip: '이름 바꾸기',
              onPressed: _rename,
              icon: const Icon(Icons.edit_outlined)),
          IconButton(
              tooltip: '기록 삭제',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Column(children: [
        _recordHeader(),
        Expanded(
          child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              // 약이 바뀌어 지난 확인 결과가 맞지 않으면 다시 확인하라고만 알린다 (결과 요약은 '자세히 보기'에)
              if (_r.last != null && !_fresh)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(children: [
                    Icon(Icons.refresh, size: 18, color: Color(0xFFB45309)),
                    SizedBox(width: 8),
                    Expanded(
                      child: KText('약 목록이나 정보가 바뀌었어요. 아래 "안전 확인"을 다시 눌러주세요.',
                          style: TextStyle(color: Color(0xFF9A3412), fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
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
                    '먹는 약을 입력해주세요. 아래의 촬영·사진첩·직접 입력 중 편한 방법을 쓰면 되고, 입력한 약은 자동으로 저장돼요.',
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
                        subtitle: _drugSub(_r.drugs[i]),
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
                      flow: true, style: TextStyle(fontSize: 12, color: AppColors.sub)),
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
                flow: true,
                style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5),
              ),
              const SizedBox(height: 20),
              // 병원 처방 기록이면 실손보험 청구: 네이버 지도의 실손24 연계로 바로 청구
              if (kShowSilson24 && !_r.otc) KeyedSubtree(key: _claimKey, child: _claimCard()),
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
        ),
      ]),
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
                    : '약 ${_r.drugs.length}개 안전 확인'),
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
    this.silson,
    this.checking = false,
    this.docsNeeded = false,
  });

  /// 연계돼 있어도 서류를 직접 올려야 하는 경우 (병원 미연계 약국)
  final bool docsNeeded;

  final bool pharmacy;
  final String name;
  final String addr;
  final bool done;

  /// 실손24 연계 여부 (null = 확인 전)
  final SilsonCheck? silson;
  final bool checking;
  final VoidCallback onPick;
  final VoidCallback onClaim;
  final ValueChanged<bool> onDone;

  @override
  Widget build(BuildContext context) {
    final (tBg, tFg) = pharmacy ? kPastelSky : kPastelTeal;
    final label = pharmacy ? '약값' : '병원비';
    final notEnabled = name.isNotEmpty && silson?.state == SilsonState.notEnabled;
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
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _SilsonBadge(silson: silson, checking: checking, docsNeeded: docsNeeded),
                ],
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
              // 청구를 마쳤으면 버튼 대신 완료 상태를 보여준다 (되돌리려면 오른쪽 '완료'를 다시 누름)
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  disabledBackgroundColor: AppColors.primarySoft,
                  disabledForegroundColor: AppColors.primaryDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                // 실손24 미연계로 확인된 곳은 서류 없이 청구할 수 없으므로 버튼을 끈다
                onPressed: done || notEnabled ? null : onClaim,
                icon: Icon(
                    done
                        ? Icons.check
                        : notEnabled
                            ? Icons.block
                            : Icons.receipt_long_outlined,
                    size: 18),
                label: KText(
                    done
                        ? '$label 청구 완료'
                        : notEnabled
                            ? '실손24 미연계'
                            : '실손24로 $label 청구',
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

/// 실손24 연계 여부 표시
class _SilsonBadge extends StatelessWidget {
  const _SilsonBadge({required this.silson, required this.checking, this.docsNeeded = false});
  final SilsonCheck? silson;
  final bool checking;
  final bool docsNeeded;

  @override
  Widget build(BuildContext context) {
    final (String text, Color bg, Color fg, IconData icon) = checking
        ? ('실손24 연계 확인 중…', AppColors.line, AppColors.sub, Icons.hourglass_empty)
        : switch (silson?.state) {
            SilsonState.enabled => docsNeeded
                ? ('실손24 연계 · 병원 서류 필요', const Color(0xFFFFF4E8), const Color(0xFF9A3412),
                    Icons.description_outlined)
                : ('실손24 연계 · 서류 없이 청구 가능', AppColors.primarySoft, AppColors.primaryDark,
                    Icons.check_circle),
            SilsonState.notEnabled => ('실손24 미연계', const Color(0xFFF1F3F5),
                const Color(0xFF6B7684), Icons.remove_circle_outline),
            _ => (
                switch (silson?.miss) {
                  SilsonMiss.noResponse => '실손24 응답 없음 · 잠시 후 다시 확인',
                  SilsonMiss.notFound => '실손24에서 찾지 못함 · 실손24에서 직접 확인',
                  SilsonMiss.ambiguous => '같은 이름이 여러 곳 · 눌러서 정확한 곳 고르기',
                  _ => '실손24 연계 여부 확인 중',
                },
                const Color(0xFFF1F3F5),
                const Color(0xFF6B7684),
                Icons.help_outline),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// 실손24 연계 조합별 청구 방법 표
void _showClaimHelp(BuildContext context) {
  const rows = [
    ('병원 ✓ · 약국 ✓', '서류 없이 바로 청구 가능', '실손24에서 병원비·약값을 한 번에 청구', Color(0xFF0B7D62)),
    ('병원 ✓ · 약국 ✕', '병원비만 서류 없이 청구 가능', '약값은 약국 영수증과 처방전(환자 보관용)을 받아 보험사 앱으로', Color(0xFF9A3412)),
    ('병원 ✕ · 약국 ✓', '서류 준비 필요', '진료비 영수증·세부내역서·처방전을 받아 실손24 또는 보험사 앱으로', Color(0xFF374151)),
    ('병원 ✕ · 약국 ✕', '서류 준비 필요', '진료비 영수증·세부내역서·처방전을 받아 보험사 앱으로 (보험사마다 필요한 서류가 다를 수 있어요)', Color(0xFF374151)),
  ];
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const KText('실손24로 청구하는 방법',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          const KText('서류 없이 청구되는지는 병원이 실손24에 연계돼 있는지가 정해요.',
              flow: true, style: TextStyle(fontSize: 13, color: AppColors.sub, height: 1.5)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.line),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 96,
                      child: KText(rows[i].$1,
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        KText(rows[i].$2,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, color: rows[i].$4)),
                        const SizedBox(height: 2),
                        KText(rows[i].$3,
                            flow: true,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.sub, height: 1.45)),
                      ]),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      ),
    ),
  );
}

