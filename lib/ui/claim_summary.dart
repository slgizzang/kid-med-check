import 'package:flutter/material.dart';

import '../logic/models.dart';
import 'theme.dart';

/// 메인 화면: 실손24로 서류 없이 바로 청구할 수 있는 기록을 한눈에 (아직 청구 안 한 것, 청구 기한 3년 안)
class ClaimSummaryCard extends StatelessWidget {
  const ClaimSummaryCard({super.key, required this.records, this.onOpen, this.checking = false});

  final List<MedRecord> records;

  /// 실손24 연계를 아직 확인 중이면 결과 대신 '확인 중'만 보여준다 (다 끝나면 한 번에)
  final bool checking;
  final ValueChanged<MedRecord>? onOpen;

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(const Duration(days: 365 * 3));
    final recent = [
      for (final r in records)
        if (!r.otc && r.createdAt.isAfter(cutoff)) r
    ];
    final all = [for (final r in recent) if (r.claimLevel == 0 && !r.fullyClaimed) r];
    final hospOnly = [for (final r in recent) if (r.claimLevel == 1 && !r.claimed) r];
    if (checking) {
      final any = recent.any((r) => !r.fullyClaimed && r.hospitalName.isNotEmpty);
      if (!any) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: softCard(radius: 18),
        child: const Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
          SizedBox(width: 10),
          Expanded(
            child: KText('실손24 서류 없이 청구 가능한 기록을 찾고 있어요',
                maxLines: 1, style: TextStyle(fontSize: 13.5, color: AppColors.sub)),
          ),
        ]),
      );
    }
    if (all.isEmpty && hospOnly.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: softCard(radius: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const KText('실손보험 청구',
            maxLines: 1,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub)),
        const SizedBox(height: 6),
        if (all.isNotEmpty)
          _group(
            icon: Icons.check_circle,
            fg: AppColors.primaryDark,
            bg: AppColors.primarySoft,
            head: '서류 없이 바로 청구 가능 ${all.length}건',
            sub: '병원·약국 모두 실손24에 연계돼 있어 병원비·약값을 한 번에 청구할 수 있어요.',
            recs: all,
          ),
        if (all.isNotEmpty && hospOnly.isNotEmpty) const SizedBox(height: 8),
        if (hospOnly.isNotEmpty)
          _group(
            icon: Icons.adjust_rounded,
            fg: const Color(0xFF9A3412),
            bg: const Color(0xFFFFF4E8),
            head: '병원비만 서류 없이 청구 가능 ${hospOnly.length}건',
            sub: '약값은 약국 영수증과 처방전(환자 보관용)으로 따로 청구해요.',
            recs: hospOnly,
          ),
      ]),
    );
  }

  Widget _group({
    required IconData icon,
    required Color fg,
    required Color bg,
    required String head,
    required String sub,
    required List<MedRecord> recs,
  }) =>
      _ClaimGroup(icon: icon, fg: fg, bg: bg, head: head, sub: sub, recs: recs, onOpen: onOpen);
}

/// 청구 가능 기록 묶음: 모두 보여주되, 많으면 접어 두고 눌러서 펼친다
class _ClaimGroup extends StatefulWidget {
  const _ClaimGroup({
    required this.icon,
    required this.fg,
    required this.bg,
    required this.head,
    required this.sub,
    required this.recs,
    this.onOpen,
  });

  final IconData icon;
  final Color fg, bg;
  final String head, sub;
  final List<MedRecord> recs;
  final ValueChanged<MedRecord>? onOpen;

  @override
  State<_ClaimGroup> createState() => _ClaimGroupState();
}

class _ClaimGroupState extends State<_ClaimGroup> {
  /// 접었을 때 보여주는 수 (이보다 많으면 '모두 보기'로 펼친다)
  static const _folded = 3;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final fg = w.fg;
    final more = w.recs.length > _folded;
    final shown = !more || _open ? w.recs : w.recs.take(_folded).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      decoration: BoxDecoration(color: w.bg, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(w.icon, size: 22, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: KText(w.head,
                maxLines: 1,
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: fg)),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 30, top: 2, right: 4, bottom: 4),
          child: KText(w.sub, flow: true, style: TextStyle(fontSize: 12.5, color: fg, height: 1.4)),
        ),
        for (final r in shown)
          InkWell(
            onTap: w.onOpen == null ? null : () => w.onOpen!(r),
            child: Padding(
              padding: const EdgeInsets.only(left: 30, top: 4, bottom: 4),
              child: Row(children: [
                Expanded(
                  child: KText(
                      '${formatDate(r.createdAt)} · ${r.hospitalName.isNotEmpty ? r.hospitalName : r.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                ),
                if (w.onOpen != null) Icon(Icons.chevron_right, size: 18, color: fg),
              ]),
            ),
          ),
        if (more)
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(left: 30, top: 6, bottom: 2),
              child: Row(children: [
                KText(_open ? '접기' : '${w.recs.length - _folded}건 더 보기',
                    maxLines: 1,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20, color: fg),
              ]),
            ),
          ),
      ]),
    );
  }
}
