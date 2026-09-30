import 'package:flutter/material.dart';

import '../logic/reaction.dart';
import '../logic/storage.dart';
import 'dashboard.dart' show kNoteBg, kNoteFg;
import 'theme.dart';

/// 복용 후 반응을 적는 시트. 저장하면 기록을, 취소하면 null을 돌려준다.
Future<ReactionNote?> showReactionSheet(
  BuildContext context, {
  required String childId,
  required String drug,
  String ingredient = '',
  String recordId = '',
}) {
  return showModalBottomSheet<ReactionNote>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _ReactionSheet(
        childId: childId, drug: drug, ingredient: ingredient, recordId: recordId),
  );
}

class _ReactionSheet extends StatefulWidget {
  const _ReactionSheet({
    required this.childId,
    required this.drug,
    required this.ingredient,
    required this.recordId,
  });

  final String childId;
  final String drug;
  final String ingredient;
  final String recordId;

  @override
  State<_ReactionSheet> createState() => _ReactionSheetState();
}

class _ReactionSheetState extends State<_ReactionSheet> {
  final _picked = <String>{};
  final _memo = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _memo.dispose();
    super.dispose();
  }

  bool get _canSave => _picked.isNotEmpty || _memo.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final n = ReactionNote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      childId: widget.childId,
      recordId: widget.recordId,
      drug: widget.drug,
      ingredient: widget.ingredient,
      date: _date,
      symptoms: [for (final s in kReactionSymptoms) if (_picked.contains(s)) s],
      memo: _memo.text.trim(),
    );
    await AppStorage.saveReaction(n);
    if (mounted) Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const KText('복용 후 반응 기록',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            KText(widget.drug,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.sub)),
            const SizedBox(height: 16),
            const KText('어떤 반응이 있었나요?',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in kReactionSymptoms)
                FilterChip(
                  label: Text(s),
                  selected: _picked.contains(s),
                  showCheckmark: false,
                  selectedColor: kNoteBg,
                  labelStyle: TextStyle(
                    color: _picked.contains(s) ? kNoteFg : AppColors.ink,
                    fontWeight: _picked.contains(s) ? FontWeight.w700 : FontWeight.w500,
                  ),
                  side: BorderSide(
                      color: _picked.contains(s) ? kNoteFg : AppColors.line),
                  onSelected: (v) => setState(() => v ? _picked.add(s) : _picked.remove(s)),
                ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _memo,
              maxLines: 3,
              minLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '메모 (예: 먹고 2시간 뒤 묽은 변 3번)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.event, size: 18, color: AppColors.sub),
              const SizedBox(width: 6),
              KText('날짜 ${formatReactionDate(_date)}',
                  style: const TextStyle(color: AppColors.ink)),
              TextButton(onPressed: _pickDate, child: const KText('바꾸기')),
            ]),
            const SizedBox(height: 4),
            const KText(
              '약 때문인지는 앱이 판단하지 않아요.\n다음에 같은 약이나 같은 성분의 약을 처방받으면 이 기록을 다시 보여드릴게요.',
              style: TextStyle(fontSize: 12, color: AppColors.sub, height: 1.5),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: const KText('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 약 카드·목록에 넣는 "지난 반응 기록" 블록
class ReactionNotesView extends StatelessWidget {
  const ReactionNotesView({super.key, required this.items, this.onDelete});

  final List<(ReactionNote, ReactionMatch)> items;
  final ValueChanged<ReactionNote>? onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(color: kNoteBg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KText('지난 반응 기록',
              style: TextStyle(color: kNoteFg, fontWeight: FontWeight.w700)),
          for (final (n, m) in items)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: KText(
                      m == ReactionMatch.sameDrug
                          ? '${formatReactionDate(n.date)} 복용 후 · ${n.summary}'
                          : '${formatReactionDate(n.date)} 같은 성분의 ${n.drug} 복용 후 · ${n.summary}',
                      style: const TextStyle(color: kNoteFg, height: 1.45),
                    ),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: '기록 지우기',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18, color: kNoteFg),
                    onPressed: () => onDelete!(n),
                  ),
              ],
            ),
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: KText('처방받을 때 의사·약사에게 알려주세요.',
                style: TextStyle(color: kNoteFg, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
