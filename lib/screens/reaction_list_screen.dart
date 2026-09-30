import 'package:flutter/material.dart';

import '../logic/models.dart';
import '../logic/reaction.dart';
import '../logic/storage.dart';
import '../ui/dashboard.dart' show kNoteBg, kNoteFg;
import '../ui/reaction_sheet.dart';
import '../ui/theme.dart';

/// 복용자가 적어둔 복용 후 반응 기록을 한곳에서 보고, 고치거나 지운다.
class ReactionListScreen extends StatefulWidget {
  const ReactionListScreen({super.key, required this.person});

  final ChildProfile person;

  @override
  State<ReactionListScreen> createState() => _ReactionListScreenState();
}

class _ReactionListScreenState extends State<ReactionListScreen> {
  List<ReactionNote>? _notes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AppStorage.reactions(widget.person.id)
      ..sort((a, b) => b.date.compareTo(a.date));
    if (mounted) setState(() => _notes = list);
  }

  Future<void> _edit(ReactionNote n) async {
    final saved = await showReactionSheet(context,
        childId: n.childId,
        drug: n.drug,
        ingredient: n.ingredient,
        recordId: n.recordId,
        items: n.items,
        existing: n);
    if (saved != null) await _load();
  }

  Future<void> _delete(ReactionNote n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const KText('이 반응 기록을 지울까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const KText('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const KText('지우기')),
        ],
      ),
    );
    if (ok != true) return;
    await AppStorage.deleteReaction(n.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    return Scaffold(
      appBar: AppBar(title: const KText('복용 후 반응 기록')),
      body: notes == null
          ? const Center(child: CircularProgressIndicator())
          : notes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: KText(
                      '아직 적어둔 반응이 없어요. 처방 기록의 약 목록에서 "반응 기록"을 눌러 적을 수 있어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.sub, height: 1.5),
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 40 + MediaQuery.of(context).padding.bottom),
                  children: [
                    KText('${widget.person.name}님의 기록 ${notes.length}개',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 4),
                    const KText('기록을 누르면 고칠 수 있어요.',
                        style: TextStyle(fontSize: 12, color: AppColors.sub)),
                    const SizedBox(height: 12),
                    for (final n in notes) _NoteCard(
                      note: n,
                      onTap: () => _edit(n),
                      onDelete: () => _delete(n),
                    ),
                  ],
                ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onTap, required this.onDelete});

  final ReactionNote note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final drugs = note.isGroup ? note.items.map((e) => e.$1).join(', ') : note.drug;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    KText(formatReactionDate(note.date),
                        maxLines: 1,
                        style: const TextStyle(fontSize: 13, color: AppColors.sub)),
                    if (note.isGroup) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: kNoteBg, borderRadius: BorderRadius.circular(6)),
                        child: const Text('처방 전체',
                            style: TextStyle(
                                fontSize: 11, color: kNoteFg, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  KText(drugs,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 4),
                  KText(note.summary,
                      style: const TextStyle(color: kNoteFg, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            IconButton(
              tooltip: '지우기',
              icon: const Icon(Icons.delete_outline, color: AppColors.sub),
              onPressed: onDelete,
            ),
          ]),
        ),
      ),
    );
  }
}
