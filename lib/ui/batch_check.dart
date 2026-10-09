import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/snapshot.dart';
import '../logic/storage.dart';
import '../screens/result_screen.dart';
import 'theme.dart';

/// 안전 확인을 안 한(또는 약이 바뀐) 기록들을 한 번에 확인한다.
/// 기록 화면의 안전 확인과 똑같은 방식(결과 화면)을 화면에 보이지 않게 하나씩 돌려 결과를 저장한다.
Future<int> runBatchCheck(BuildContext context, ChildProfile person, List<MedRecord> records) async {
  final done = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BatchDialog(person: person, records: records),
  );
  return done ?? 0;
}

class _BatchDialog extends StatefulWidget {
  const _BatchDialog({required this.person, required this.records});
  final ChildProfile person;
  final List<MedRecord> records;

  @override
  State<_BatchDialog> createState() => _BatchDialogState();
}

class _BatchDialogState extends State<_BatchDialog> {
  var _i = 0;
  var _saved = 0;
  var _stop = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  /// 한 기록이 너무 오래 걸리면(네트워크 문제 등) 건너뛴다
  void _arm() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 60), _next);
  }

  Future<void> _finished(ResultSnapshot snap) async {
    final r = widget.records[_i];
    r.last = snap;
    await AppStorage.saveRecord(r);
    _saved++;
    _next();
  }

  void _next() {
    if (!mounted) return;
    if (_stop || _i + 1 >= widget.records.length) {
      _timeout?.cancel();
      Navigator.pop(context, _saved);
      return;
    }
    setState(() => _i++);
    _arm();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.records[_i];
    final total = widget.records.length;
    return AlertDialog(
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        KText('안전 확인 중… ${_i + 1}/$total',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        KText(r.title, maxLines: 1, style: const TextStyle(fontSize: 13, color: AppColors.sub)),
        const SizedBox(height: 14),
        LinearProgressIndicator(value: total == 0 ? null : (_i) / total, minHeight: 4),
        // 실제 확인은 기록 화면과 같은 결과 화면으로 (보이지 않게)
        Offstage(
          child: SizedBox(
            width: 360,
            height: 640,
            child: ResultScreen(
              key: ValueKey(r.id),
              child: widget.person,
              names: List.of(r.drugs),
              recordId: r.id,
              asOf: r.createdAt,
              letters: Map.of(r.safetyLetters),
              onFinished: _finished,
            ),
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => setState(() => _stop = true),
          child: KText(_stop ? '이번 기록까지만 확인해요' : '그만하기', maxLines: 1),
        ),
      ],
    );
  }
}
