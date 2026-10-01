import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/claim.dart';
import '../logic/models.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';

/// 실손보험 청구 준비: 이 복용 기록의 사진을 모아 보험사 앱·실손24로 보내기 쉽게 정리한다.
/// 앱이 청구를 대신 접수하지는 않는다.
class ClaimScreen extends StatefulWidget {
  const ClaimScreen({super.key, required this.child, required this.record});

  final ChildProfile child;
  final MedRecord record;

  @override
  State<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends State<ClaimScreen> {
  MedRecord get _r => widget.record;
  bool _busy = false;

  ClaimInfo get _info => mergeClaims(_r.photos.map((p) => parseReceipt(p.text)));

  Future<void> _add(ImageSource source) async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 3200, imageQuality: 92);
    } catch (_) {
      return;
    }
    if (file == null) return;
    setState(() => _busy = true);
    var text = '';
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      text = (await recognizer.processImage(InputImage.fromFilePath(file.path))).text;
    } catch (_) {
    } finally {
      await recognizer.close();
    }
    try {
      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/photos');
      await dir.create(recursive: true);
      final dst = '${dir.path}/${_r.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(file.path).copy(dst);
      _r.photos.add(RecordPhoto(path: dst, text: text, at: DateTime.now()));
      await AppStorage.saveRecord(_r);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(RecordPhoto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const KText('이 사진을 지울까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const KText('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const KText('지우기')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      File(p.path).deleteSync();
    } catch (_) {}
    setState(() => _r.photos.remove(p));
    await AppStorage.saveRecord(_r);
  }

  String _summary() {
    final i = _info;
    return [
      '[실손보험 청구 자료] ${widget.child.name}',
      '조제일: ${formatDate(i.date ?? _r.createdAt)}',
      if (i.pharmacy != null) '약국: ${i.pharmacy}',
      if (i.amount != null) '본인부담금(사진에서 읽은 값): ${formatWon(i.amount!)}',
      if (_r.drugs.isNotEmpty) '약: ${_r.drugs.join(', ')}',
    ].join('\n');
  }

  Future<void> _share() async {
    final files = _r.photos.where((p) => File(p.path).existsSync()).map((p) => XFile(p.path)).toList();
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KText('먼저 영수증이나 처방전 사진을 추가해주세요.')));
      return;
    }
    await Share.shareXFiles(files, text: _summary(), subject: '실손보험 청구 자료');
  }

  Future<void> _openSilson24() async {
    // 보험개발원 '실손24' 앱 (플레이스토어에서 검색해 열기)
    final uri = Uri.parse('https://play.google.com/store/search?q=%EC%8B%A4%EC%86%9024&c=apps');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    return Scaffold(
      appBar: AppBar(title: const KText('실비 보험 청구 준비')),
      body: Stack(children: [
        ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 40 + MediaQuery.of(context).padding.bottom),
          children: [
            const KText('약국비도 실손보험으로 청구할 수 있어요.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            const KText('사진을 모아 보험사 앱이나 실손24로 보내기 쉽게 정리해 드려요. 청구 접수는 보험사 앱에서 해주세요.',
                style: TextStyle(color: AppColors.sub, height: 1.5)),
            const SizedBox(height: 16),
            _Card(
              title: '사진에서 읽은 정보',
              child: Column(children: [
                _Row('조제일', formatDate(i.date ?? _r.createdAt)),
                _Row('약국', i.pharmacy ?? '찾지 못함'),
                _Row('본인부담금', i.amount != null ? formatWon(i.amount!) : '찾지 못함', strong: true),
                _Row('약', _r.drugs.isEmpty ? '없음' : '${_r.drugs.length}개'),
                const SizedBox(height: 6),
                const KText('사진 글자를 읽은 값이라 틀릴 수 있어요. 청구할 때 영수증과 한 번 맞춰보세요.',
                    style: TextStyle(fontSize: 12, color: AppColors.sub)),
              ]),
            ),
            _Card(
              title: '사진 ${_r.photos.length}장',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: '촬영',
                    onPressed: () => _add(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined)),
                IconButton(
                    tooltip: '사진첩',
                    onPressed: () => _add(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined)),
              ]),
              child: _r.photos.isEmpty
                  ? const KText('약국 영수증(약제비 영수증)을 찍어 추가해주세요.',
                      style: TextStyle(color: AppColors.sub))
                  : GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (final p in _r.photos)
                          GestureDetector(
                            onLongPress: () => _remove(p),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: File(p.path).existsSync()
                                  ? Image.file(File(p.path), fit: BoxFit.cover, cacheWidth: 300)
                                  : Container(color: AppColors.line),
                            ),
                          ),
                      ],
                    ),
            ),
            if (_r.photos.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: KText('사진을 길게 누르면 지울 수 있어요.',
                    style: TextStyle(fontSize: 12, color: AppColors.sub)),
              ),
            const _Card(
              title: '보통 필요한 서류',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Check('약제비 영수증 (약국에서 받은 영수증)'),
                _Check('처방전 또는 약제비 계산서 (보험사에 따라)'),
                _Check('병원 진료비 영수증 (병원비도 함께 청구할 때)'),
                SizedBox(height: 6),
                KText('보험사마다 다를 수 있어요. 소액은 영수증만으로 되는 경우가 많아요.',
                    style: TextStyle(fontSize: 12, color: AppColors.sub)),
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share),
              label: const KText('사진·정보 보내기 (보험사 앱·카톡·메일)'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openSilson24,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const KText('실손24 앱 열기'),
            ),
            const SizedBox(height: 8),
            const KText(
              '실손24는 보험개발원의 실손보험 청구 앱이에요. 참여한 병원·약국이면 서류 없이 청구할 수 있어요.',
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
                  KText('사진을 읽는 중…'),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: KText(title,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.k, this.v, {this.strong = false});
  final String k, v;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
              width: 80,
              child: Text(k, style: const TextStyle(color: AppColors.sub))),
          Expanded(
            child: KText(v,
                style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                    fontSize: strong ? 17 : 15)),
          ),
        ]),
      );
}

class _Check extends StatelessWidget {
  const _Check(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.check_circle_outline, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: KText(text, style: const TextStyle(color: AppColors.ink))),
        ]),
      );
}
