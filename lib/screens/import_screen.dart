import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/hira_import.dart';
import '../logic/models.dart';
import '../logic/office_decrypt.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';

/// 심평원 '내가 먹는 약 한눈에' 투약이력 엑셀을 불러와 처방 기록으로 만든다.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.person});

  final ChildProfile person;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _busy = false;
  List<ImportedVisit>? _visits;
  String? _openedWith;
  String? _error;

  Future<void> _openSite() async {
    final ok = await launchUrl(Uri.parse(kHiraUrl), mode: LaunchMode.inAppBrowserView);
    if (!ok && mounted) {
      await launchUrl(Uri.parse(kHiraUrl), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    await _open(bytes);
  }

  Future<void> _open(Uint8List bytes, {String? password}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 비밀번호는 저장하지 않고 이번에 여는 데만 쓴다
      const people = <(String, DateTime)>[];
      // 암호 풀기는 계산이 많아 화면이 멈추지 않게 별도 스레드에서
      final r = await compute(HiraImport.openArgs, (bytes, people, password));
      setState(() {
        _visits = r.visits;
        _openedWith = r.passwordOwner;
      });
    } on OfficeFileException catch (e) {
      if (e.wrongPassword) {
        setState(() => _busy = false);
        final pw = await _askPassword(retry: password != null);
        if (pw != null) return _open(bytes, password: pw);
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      final msg = '$e'.split('\n').first;
      setState(() => _error =
          '파일을 읽지 못했어요.\n(${msg.length > 120 ? '${msg.substring(0, 120)}…' : msg})');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword({required bool retry}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const KText('파일 비밀번호'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KText(retry
                ? '비밀번호가 맞지 않아요. 다시 입력해주세요.'
                : '파일을 내려받은 사람(로그인한 사람)의 생년월일 8자리를 입력해주세요.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                hintText: '생년월일 8자리 (예: 19900101)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const KText('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text), child: const KText('열기')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final v = _visits;
    if (v == null || v.isEmpty) return;
    final (added, skipped) = await AppStorage.importVisits(widget.person.id, v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: KText(skipped > 0
          ? '복용 기록 $added개를 만들었어요. 이미 있던 $skipped개는 건너뛰었어요.'
          : '복용 기록 $added개를 만들었어요.'),
    ));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final visits = _visits;
    return Scaffold(
      appBar: AppBar(title: const KText('지난 1년 기록 불러오기')),
      body: Stack(children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 40 + MediaQuery.of(context).padding.bottom),
          children: [
            KText('${widget.person.name}님의 투약이력을 $kHiraServiceName에서 받아와요.',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 16),
            _Step(
              n: 1,
              title: '사이트에서 로그인하고 조회하기',
              body: '아래 버튼으로 사이트를 열고, 본인 인증 후 투약이력을 조회하세요. '
                  '만 14세 미만 자녀는 법정대리인(부모)이 사이트에서 먼저 사전 등록을 해야 조회돼요.',
              action: OutlinedButton.icon(
                onPressed: _openSite,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const KText('내가 먹는 약 한눈에 열기'),
              ),
            ),
            const _Step(
              n: 2,
              title: '엑셀로 내려받기',
              body: '조회 화면에서 엑셀 파일로 저장하세요. 파일은 내려받은 사람의 생년월일 8자리로 잠겨 있어요.',
            ),
            _Step(
              n: 3,
              title: '내려받은 파일 고르기',
              body: '파일을 열 때 비밀번호로 내려받은 사람의 생년월일 8자리(예: 19900101)를 입력해요. '
                  '자녀 기록을 부모가 내려받았다면 부모 생년월일이에요. 비밀번호는 저장하지 않아요.',
              action: FilledButton.icon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const KText('파일 선택'),
              ),
            ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12)),
                child: KText(_error!, style: const TextStyle(color: Color(0xFFB71C1C))),
              ),
            if (visits != null) ...[
              const SizedBox(height: 20),
              if (_openedWith != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KText('$_openedWith님 생년월일로 파일을 열었어요.',
                      style: const TextStyle(fontSize: 13, color: AppColors.sub)),
                ),
              SectionTitle('불러온 처방 ${visits.length}건'),
              if (visits.isEmpty)
                const KText('파일에 투약 내역이 없어요.')
              else ...[
                for (final v in visits)
                  Card(
                    child: ListTile(
                      title: KText(v.title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: KText('${formatDate(v.date)} · ${v.drugs.join(', ')}',
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _save,
                  child: const KText('복용 기록으로 저장'),
                ),
                const SizedBox(height: 8),
                const KText('이미 불러온 처방은 다시 저장하지 않아요. 원본 파일은 앱에 보관하지 않아요.',
                    style: TextStyle(fontSize: 12, color: AppColors.sub)),
              ],
            ],
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
                  KText('파일을 여는 중…'),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body, this.action});

  final int n;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.mint,
            child: Text('$n',
                style: const TextStyle(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KText(title,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 4),
                KText(body,
                    style: const TextStyle(fontSize: 13, color: AppColors.sub, height: 1.5)),
                if (action != null) ...[const SizedBox(height: 10), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
