import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/models.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';
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

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _addNames(Iterable<String> names) {
    var added = 0;
    setState(() {
      for (final raw in names) {
        final n = DrugNameExtractor.toSearchName(raw);
        if (n.length >= 2 && !_r.drugs.contains(n)) {
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
        title: const Text('기록 이름'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 소아과 감기약'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('저장')),
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
        title: const Text('이 기록을 삭제할까요?'),
        content: const Text('기록에 담긴 약 목록도 함께 지워져요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
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
            const Text('약 이름 직접 입력',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('여러 개는 쉼표나 줄바꿈으로 구분하세요.',
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
              child: const Text('추가'),
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _rename,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(_r.title, overflow: TextOverflow.ellipsis)),
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
              Text(
                '${widget.child.name} · ${widget.child.ageLabel} · ${formatDate(_r.createdAt)}',
                style: const TextStyle(color: AppColors.sub),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: _AddTile(
                    icon: Icons.photo_camera_outlined,
                    label: '촬영',
                    onTap: () => _scan(ImageSource.camera),
                    primary: true,
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
              const SizedBox(height: 26),
              SectionTitle('약 목록',
                  trailing: Text('${_r.drugs.length}개',
                      style: const TextStyle(color: AppColors.sub))),
              if (_r.drugs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Text(
                    '처방전이나 약봉지를 찍거나, 약 이름을 직접 입력해 추가하세요.\n추가한 약은 자동으로 저장돼요.',
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
                        title: Text(_r.drugs[i],
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: IconButton(
                          tooltip: '빼기',
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() => _r.drugs.removeAt(i));
                            _save();
                          },
                        ),
                      ),
                    ],
                  ]),
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
                    Text('글자를 읽는 중…'),
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
            label: Text('${_r.drugs.length}개 약 금기 확인하기'),
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
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: primary ? null : Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: primary ? Colors.white : AppColors.primary),
              const SizedBox(height: 8),
              Text(label,
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
