import 'package:flutter/material.dart';

import '../logic/models.dart';
import 'theme.dart';

/// 복용 기록의 병원 이름 (없으면 기록 이름에서 병원처럼 보이는 부분, 그것도 없으면 빈 문자열)
String recordPlace(MedRecord r) {
  if (r.otc) return r.pharmacy.trim();
  if (r.hospital.trim().isNotEmpty) return r.hospital.trim();
  final t = r.title
      .replaceFirst(RegExp(r'^\s*\d{1,2}월\s*\d{1,2}일\s*'), '')
      .replaceAll(RegExp(r'^(처방|약국 구입)$'), '')
      .trim();
  return RegExp(r'(의원|병원|센터|클리닉|보건소)').hasMatch(t) ? t : '';
}

/// 기록 화면·안전 확인 결과 화면 위쪽 초록 띠: 어느 병원(약국)에서 언제 받은 약인지
class RecordHeader extends StatelessWidget {
  const RecordHeader({super.key, required this.record, required this.person});
  final MedRecord record;
  final ChildProfile person;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final d = r.createdAt;
    final dateLabel = '${d.year}년 ${d.month}월 ${d.day}일';
    final place = recordPlace(r);
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration:
              BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(14)),
          child: Icon(r.otc ? Icons.local_pharmacy_outlined : Icons.receipt_long_outlined,
              color: AppColors.onPrimary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KText(place.isNotEmpty ? place : r.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onPrimary)),
            const SizedBox(height: 4),
            KText(
                '$dateLabel ${r.otc ? '구입' : '처방'} · ${person.name} ${formatAge(person.ageInMonths(r.createdAt))}',
                maxLines: 2,
                style: const TextStyle(fontSize: 13.5, color: Color(0xE6FFFFFF))),
          ]),
        ),
      ]),
    );
  }
}
