import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/drug_name_extractor.dart';
import '../logic/models.dart';
import '../logic/storage.dart';
import 'child_edit_screen.dart';
import 'confirm_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ChildProfile> _children = [];
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
    final sel = await AppStorage.selectedChildId();
    final key = await AppStorage.apiKey();
    if (!mounted) return;
    setState(() {
      _children = children;
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

  bool _ensureReady() {
    if (_selected == null) {
      _snack('먼저 아이 정보를 추가해주세요.');
      return false;
    }
    if (!_hasKey) {
      _snack('설정에서 공공데이터 인증키를 먼저 입력해주세요.');
      return false;
    }
    return true;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scan(ImageSource source) async {
    if (!_ensureReady()) return;
    final XFile? file;
    try {
      file = await ImagePicker()
          .pickImage(source: source, maxWidth: 2400, imageQuality: 90);
    } catch (e) {
      _snack('사진을 가져오지 못했어요: $e');
      return;
    }
    if (file == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('글자를 읽는 중…')),
        ]),
      ),
    );

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
    Navigator.pop(context); // 로딩 닫기

    if (error != null) {
      _snack('글자 인식에 실패했어요. 직접 입력해주세요. ($error)');
    }
    final candidates = DrugNameExtractor.extract(text);
    _goConfirm(candidates, text);
  }

  void _goConfirm(List<String> candidates, String rawText) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmScreen(
          child: _selected!,
          initialNames: candidates,
          rawText: rawText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('아이 약 안심체크'),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_hasKey)
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.vpn_key_outlined),
                      title: const Text('인증키 설정이 필요해요'),
                      subtitle: const Text('공공데이터포털에서 받은 키를 입력해주세요.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openSettings,
                    ),
                  ),
                const SizedBox(height: 4),
                Text('누구의 약인가요?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _children)
                      GestureDetector(
                        onLongPress: () => _editChild(c),
                        child: ChoiceChip(
                          label: Text('${c.name} · ${c.ageLabel}'),
                          selected: c.id == _selectedId,
                          onSelected: (_) {
                            setState(() => _selectedId = c.id);
                            AppStorage.setSelectedChildId(c.id);
                          },
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text(_children.isEmpty ? '아이 정보 추가' : '추가'),
                      onPressed: () => _editChild(),
                    ),
                  ],
                ),
                if (_children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('이름을 길게 누르면 수정할 수 있어요.',
                        style: theme.textTheme.bodySmall),
                  ),
                const SizedBox(height: 28),
                Text('약 확인하기', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('처방전 · 약봉지 촬영'),
                  onPressed: () => _scan(ImageSource.camera),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('갤러리 사진에서 읽기'),
                  onPressed: () => _scan(ImageSource.gallery),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('약 이름 직접 입력'),
                  onPressed: () {
                    if (_ensureReady()) _goConfirm(const [], '');
                  },
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '식품의약품안전처 DUR(의약품 안전사용 서비스)의 "특정연령대 금기" '
                      '정보와 아이 나이를 비교해 알려드려요.\n\n'
                      '연령금기 약도 의사가 치료상 필요하다고 판단하면 처방할 수 있어요. '
                      '경고가 나와도 약을 임의로 끊지 말고, 약국이나 병원에 꼭 확인해주세요.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
