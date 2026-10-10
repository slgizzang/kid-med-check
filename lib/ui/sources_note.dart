import 'package:flutter/material.dart';

import 'theme.dart';

/// 화면 맨 아래 출처 안내 (메인 화면·안전 확인 결과 화면 공통). 항목마다 한 줄씩.
class SourcesNote extends StatelessWidget {
  const SourcesNote({super.key});

  static const _style = TextStyle(fontSize: 12, color: Color(0xFF4E5968), height: 1.45);

  static Widget _line(String t, {bool bold = false}) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(t,
            maxLines: 1,
            softWrap: false,
            style: bold ? _style.copyWith(fontWeight: FontWeight.w700) : _style),
      );

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.sub, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line('출처:', bold: true),
                  _line('의약품안전사용서비스(DUR)'),
                  _line('e약은요'),
                  _line('의약품 제품 허가정보'),
                  _line('식약처 의약품 회수·판매중지 정보'),
                  _line('심평원 투약이력 (안전성 서한)'),
                  const SizedBox(height: 6),
                  _line('경고가 나와도 임의로 끊지 말고 약사·의사와 상의하세요.'),
                ],
              ),
            ),
          ],
        ),
      );
}
