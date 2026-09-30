import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/models.dart';
import '../logic/reaction.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';
import '../ui/dashboard.dart';
import '../ui/reaction_sheet.dart';
import 'confirm_screen.dart';
import 'reaction_list_screen.dart';
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
    ].join('|');
  }

  /// 지난 결과가 지금 목록·정보와 같은지
  bool get _fresh =>
      _r.last != null &&
      _r.last!.matches(_r.drugs) &&
      _r.last!.pregnant == widget.child.pregnant &&
      _r.last!.nursing == widget.child.nursing;

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
    final hits = reactionsFor(_notes, drug, ingr);
    if (hits.isEmpty) return null;
    final (n, m) = hits.first;
    return KText('반응 기록 · ${reactionLine(n, m)}',
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
                if (!_r.last!.matches(_r.drugs) ||
                    _r.last!.pregnant != widget.child.pregnant ||
                    _r.last!.nursing != widget.child.nursing)
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
                  stale: !_r.last!.matches(_r.drugs) ||
                      _r.last!.pregnant != widget.child.pregnant ||
                      _r.last!.nursing != widget.child.nursing,
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
                              size: 20, color: AppColors.primary),
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
              if (_r.drugs.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ReactionListScreen(person: widget.child)));
                      await _loadNotes();
                    },
                    icon: const Icon(Icons.list_alt, size: 20),
                    label: const KText('적어둔 반응 기록 보기·고치기'),
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
                '촬영·사진첩은 사진 속 글자를 읽는 기술(OCR)로 약 이름을 찾아요. '
                '약 이름이 아닌 단어도 함께 잡힐 수 있어요. '
                '다음 화면에서 처방받은 약만 골라 추가해주세요.',
                style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5),
              ),
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
              Icon(icon, size: 22, color: primary ? Colors.white : AppColors.primary),
              const SizedBox(height: 4),
              KText(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: primary ? Colors.white : AppColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
