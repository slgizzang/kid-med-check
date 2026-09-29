# 아이 약 안심체크 (kid_med_check)

처방전·약봉지를 찍거나 약 이름을 입력하면, 식품의약품안전처 **DUR 특정연령대금기** 정보를 조회해
아이 나이(만 나이, 개월 단위)에 금기인 약인지 알려주는 안드로이드 앱(Flutter)입니다.

## 동작 흐름
1. 아이 이름·생년월일 등록 (휴대폰에만 저장)
2. 처방전/약봉지 촬영 → ML Kit 한국어 OCR(기기 안에서 처리) → 약 이름 후보 추출
3. 후보 확인·수정·직접 추가
4. `DURPrdlstInfoService03/getSpcifyAgrdeTabooInfoList03` 에 `itemName`으로 조회
5. 금기 문구(예: "만 12세 미만")에서 연령 조건을 읽어 아이 나이와 비교
   - 🔴 연령금기 해당 / 🟡 문구 자동판단 불가 / 🔵 목록에 있지만 금기 연령 아님 / 🟢 목록에 없음

## 인증키
- data.go.kr → "식품의약품안전처_의약품안전사용서비스(DUR)품목정보" 활용신청
- 앱의 **설정**에 일반 인증키(Decoding)를 입력하거나,
- GitHub 저장소 Settings → Secrets → Actions 에 `DUR_API_KEY` 로 넣으면 빌드된 APK에 기본값으로 들어갑니다.
  (공개 저장소라도 키가 코드에 노출되지 않습니다. 단, APK를 남에게 배포하면 APK 안에서 키를 꺼낼 수 있어요.)

## 빌드 (휴대폰만으로)
GitHub에 이 폴더 내용을 올리면 `.github/workflows/build-apk.yml` 이
`flutter create` → `tool/prepare_android.py` → 테스트 → APK 빌드 후 **Releases** 에 APK를 올립니다.
휴대폰에서 저장소 → Releases → `.apk` 를 눌러 설치(출처를 알 수 없는 앱 허용 필요).

## PC에서 빌드
```bash
flutter create --platforms=android --org com.kidmedcheck --project-name kid_med_check .
python3 tool/prepare_android.py
flutter test
flutter run
```

## 한계 (꼭 읽기)
- 약 **제품명** 부분일치로 조회합니다. 성분명만 입력하면 안 나올 수 있어요.
- OCR은 틀릴 수 있어 반드시 사용자가 이름을 확인하게 되어 있어요.
- 연령금기 약도 의사가 치료상 필요하면 사유를 적고 처방할 수 있습니다. 경고가 나와도 임의로 중단하지 말고 약사·의사에게 확인하도록 안내합니다.
- 식약처 실제 응답 필드명이 바뀌어도 동작하도록 파싱을 방어적으로 짰지만, 첫 실행 때 결과 화면의 "금기 내용"이 제대로 나오는지 확인이 필요합니다.
- 한국의약품안전관리원 DUR 데이터는 상업적 이용 시 사전 승인이 필요합니다.
