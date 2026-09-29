"""`flutter create --platforms=android .` 로 만든 android/ 폴더를 이 앱에 맞게 고친다.

- 인터넷 권한 추가 (릴리스 빌드는 기본으로 없음)
- 앱 이름 한글로
- ML Kit 한국어 글자인식 모델 의존성 추가
- R8(코드 축소)에서 ML Kit 다른 언어 클래스 누락 경고 무시
"""
import pathlib
import re
import sys

APP_LABEL = "아이 약 안심체크"
KOREAN_OCR = "com.google.mlkit:text-recognition-korean:16.0.1"

root = pathlib.Path(__file__).resolve().parent.parent
app = root / "android" / "app"

# 1) AndroidManifest
manifest = app / "src" / "main" / "AndroidManifest.xml"
m = manifest.read_text(encoding="utf-8")
if "android.permission.INTERNET" not in m:
    m = re.sub(
        r"(<manifest[^>]*>)",
        r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>',
        m,
        count=1,
    )
m = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', m, count=1)
manifest.write_text(m, encoding="utf-8")

# 2) app/build.gradle(.kts)
kts = app / "build.gradle.kts"
groovy = app / "build.gradle"
if kts.exists():
    g = kts.read_text(encoding="utf-8")
    if KOREAN_OCR not in g:
        g += f'\ndependencies {{\n    implementation("{KOREAN_OCR}")\n}}\n'
    kts.write_text(g, encoding="utf-8")
elif groovy.exists():
    g = groovy.read_text(encoding="utf-8")
    if KOREAN_OCR not in g:
        g += f"\ndependencies {{\n    implementation '{KOREAN_OCR}'\n}}\n"
    groovy.write_text(g, encoding="utf-8")
else:
    sys.exit("android/app/build.gradle(.kts) 를 찾지 못했습니다. 먼저 flutter create 를 실행하세요.")

# 3) ProGuard/R8 규칙 (Flutter 플러그인이 app/proguard-rules.pro 를 자동 적용)
(app / "proguard-rules.pro").write_text(
    "\n".join(
        [
            "-dontwarn com.google.mlkit.vision.text.chinese.**",
            "-dontwarn com.google.mlkit.vision.text.devanagari.**",
            "-dontwarn com.google.mlkit.vision.text.japanese.**",
            "-keep class com.google.mlkit.vision.text.korean.** { *; }",
            "",
        ]
    ),
    encoding="utf-8",
)

print("android/ 설정 완료")
