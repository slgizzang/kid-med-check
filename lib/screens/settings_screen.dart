import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/dur_api.dart';
import '../logic/storage.dart';
import '../ui/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _key = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  String? _testResult;

  static const _portalUrl = 'https://www.data.go.kr/data/15059486/openapi.do';

  @override
  void initState() {
    super.initState();
    AppStorage.apiKey().then((k) {
      if (mounted) setState(() => _key.text = k);
    });
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AppStorage.setApiKey(_key.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: KText('저장했어요.')));
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final key = kHasBuiltInKey ? kBuiltInApiKey : _key.text;
      final rows = await DurApi(key).searchAgeTaboo('정');
      _testResult = '연결 성공! (샘플 조회 ${rows.length}건)';
    } catch (e) {
      _testResult = '실패: $e';
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const KText('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (kHasBuiltInKey) ...[
            KText('데이터 연결', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const KText('식품의약품안전처 DUR 정보에 연결돼 있어요. 조회가 안 될 때 눌러서 확인해보세요.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _testing ? null : _test,
              child: KText(_testing ? '확인 중…' : '연결 확인'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              KText(_testResult!),
            ],
          ] else ...[
            KText('공공데이터 인증키', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '일반 인증키 (Decoding)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton(onPressed: _save, child: const KText('저장')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: KText(_testing ? '확인 중…' : '연결 테스트'),
                ),
              ),
            ]),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              KText(_testResult!),
            ],
            const SizedBox(height: 28),
            KText('인증키 받는 법', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const KText(
              '1. 공공데이터포털(data.go.kr)에 가입·로그인\n'
              '2. "식품의약품안전처_의약품안전사용서비스(DUR)품목정보" 검색 → 활용신청\n'
              '3. 마이페이지 → 데이터활용 → 개발계정에서 "일반 인증키(Decoding)" 복사\n'
              '4. 위 칸에 붙여넣고 저장 (승인 직후엔 1~2시간 뒤부터 동작할 수 있어요)',
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(child: SelectableText(_portalUrl)),
              IconButton(
                tooltip: '주소 복사',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: _portalUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: KText('주소를 복사했어요.')));
                },
              ),
            ]),
          ],
          const SizedBox(height: 28),
          KText('안내', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const KText(
            '• 사진은 휴대폰 안에서만 글자 인식에 쓰이고, 서버로 보내지 않아요.\n'
            '• 식약처에는 약 이름만 조회해요. 복용자 이름·생일은 휴대폰에만 저장돼요.\n'
            '• 이 앱은 참고용이며 의사·약사의 판단을 대신하지 않아요.',
          ),
        ],
      ),
    );
  }
}
