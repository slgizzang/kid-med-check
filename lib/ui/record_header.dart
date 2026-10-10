import 'package:flutter/material.dart';

import '../logic/models.dart';
import 'theme.dart';

/// 복용 기록의 병원 이름 (직접 산 약이면 약국 이름). 모르면 빈 문자열.
String recordPlace(MedRecord r) => r.otc ? r.pharmacy.trim() : r.hospitalName;

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
