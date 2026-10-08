/// 식약처 의약품 회수·판매중지 정보와 복용 기록 대조.
/// 전체 목록이 1천 건 남짓이라 하루 한 번 통째로 받아 휴대폰에 두고, 기록의 약 이름과 맞춘다.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'dur_api.dart';
import 'models.dart';

class Recall {
  Recall({
    required this.product,
    this.company = '',
    this.reason = '',
    this.forced = false,
    this.date,
    this.itemSeq = '',
  });

  /// 제품명 (식약처 표기 그대로)
  final String product;
  final String company;

  /// 회수 사유
  final String reason;

  /// 식약처 회수 명령(강제)인지. 아니면 업체 자진 회수.
  final bool forced;

  /// 회수 명령(공표)일
  final DateTime? date;
  final String itemSeq;

  Map<String, dynamic> toJson() => {
        'p': product,
        'c': company,
        'r': reason,
        if (forced) 'f': true,
        if (date != null) 'd': date!.toIso8601String(),
        if (itemSeq.isNotEmpty) 's': itemSeq,
      };

  factory Recall.fromJson(Map<String, dynamic> j) => Recall(
        product: '${j['p'] ?? ''}',
        company: '${j['c'] ?? ''}',
        reason: '${j['r'] ?? ''}',
        forced: j['f'] == true,
        date: DateTime.tryParse('${j['d'] ?? ''}'),
        itemSeq: '${j['s'] ?? ''}',
      );

  /// 식약처 API 한 행
  static Recall? fromApi(Map<String, dynamic> m) {
    String s(String k) {
      final v = m[k];
      return v == null || '$v' == 'null' ? '' : '$v'.trim();
    }

    final p = s('PRDUCT');
    if (p.isEmpty) return null;
    final d = s('RECALL_COMMAND_DATE').isNotEmpty ? s('RECALL_COMMAND_DATE') : s('RTRVL_CMMND_DT');
    DateTime? date;
    final m8 = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(d.replaceAll(RegExp(r'[^0-9]'), ''));
    if (m8 != null) {
      date = DateTime(int.parse(m8.group(1)!), int.parse(m8.group(2)!), int.parse(m8.group(3)!));
    }
    return Recall(
      product: p,
      company: s('ENTRPS'),
      reason: s('RTRVL_RESN'),
      forced: s('ENFRC_YN').toUpperCase() == 'Y',
      date: date,
      itemSeq: s('ITEM_SEQ'),
    );
  }
}

/// 이름 비교용: 앞 번호("1."), 괄호 속, 띄어쓰기, 표기 차이(밀리그람/밀리그램)를 없앤다.
String recallKey(String name) => name
    .replaceFirst(RegExp(r'^\s*\d+\s*[.)]\s*'), '')
    .replaceAll(RegExp(r'[(\[（][^)\]）]*[)\]）]'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAll('밀리그람', '밀리그램')
    .replaceAll('마이크로그람', '마이크로그램')
    .toLowerCase();

/// 복용 기록의 약 중 회수된 것
/// 처방·구매일로부터 이 기간(일) 안에 나온 회수만 알린다
const kRecallWindowRx = 183;
const kRecallWindowOtc = 730;

class RecallHit {
  RecallHit(this.record, this.drug, this.recall, {this.injected = false});
  final MedRecord record;
  final String drug;
  final Recall recall;

  /// 주사제 — 병원에서 이미 맞은 약이라 집에 남은 약이 없다 (조용한 안내만)
  final bool injected;
}

/// 기록과 회수 목록 대조. 이름이 정확히 같은 제품만, 회수일이 처방·구입일 이후(같은 날 포함)이고
/// 처방약은 6개월, 직접 산 약은 2년 안에 나온 것만.
/// 회수가 먼저 있었으면 그 뒤에 받은 약은 회수 대상 제조번호가 아니므로 알리지 않는다.
List<RecallHit> matchRecalls(List<MedRecord> records, List<Recall> recalls) {
  final byKey = <String, List<Recall>>{};
  for (final r in recalls) {
    final k = recallKey(r.product);
    if (k.length >= 2) (byKey[k] ??= []).add(r);
  }
  final out = <RecallHit>[];
  for (final rec in records) {
    for (final d in rec.drugs) {
      // 주사제는 병원에서 이미 맞은 약이라 반납할 약이 없다 → 조용한 안내로 따로 표시
      final injected = isInjection(d);
      for (final r in byKey[recallKey(d)] ?? const <Recall>[]) {
        final when = r.date;
        final day = DateTime(rec.createdAt.year, rec.createdAt.month, rec.createdAt.day);
        if (when == null || when.isBefore(day)) continue;
        // 너무 오래 지난 약은 집에 남아 있을 가능성이 낮다:
        // 처방약(약국에서 덜어 준 약)은 6개월, 직접 산 약(원래 포장, 유통기한 2~3년)은 2년까지만
        if (when.difference(day).inDays > (rec.otc ? kRecallWindowOtc : kRecallWindowRx)) continue;
        out.add(RecallHit(rec, d, r, injected: injected));
      }
    }
  }
  out.sort((a, b) => (b.recall.date ?? DateTime(0)).compareTo(a.recall.date ?? DateTime(0)));
  return out;
}

class RecallStore {
  static const _host = 'apis.data.go.kr';
  static const _path =
      '/1471000/MdcinRtrvlSleStpgeInfoService05/getMdcinRtrvlSleStpgelList05';
  static const _prefKey = 'recalls1';
  static List<Recall>? _mem;

  /// 회수 목록 (하루 한 번만 새로 받음). 받지 못하면 저장해 둔 목록, 그것도 없으면 빈 목록.
  static Future<List<Recall>> load(String apiKey, {http.Client? client}) async {
    if (_mem != null) return _mem!;
    SharedPreferences? p;
    List<Recall>? saved;
    try {
      p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map;
        saved = [
          for (final e in (j['i'] as List)) Recall.fromJson(Map<String, dynamic>.from(e as Map))
        ];
        final t = DateTime.fromMillisecondsSinceEpoch(j['t'] as int);
        if (DateTime.now().difference(t) < const Duration(hours: 24)) return _mem = saved;
      }
    } catch (_) {}
    apiKey = DurApi.normalizeKey(apiKey);
    if (apiKey.isEmpty) return saved ?? const [];
    try {
      final c = client ?? http.Client();
      final all = <Recall>[];
      for (var page = 1; page <= 10; page++) {
        final uri = Uri.https(_host, _path, {
          'serviceKey': apiKey,
          'type': 'json',
          'pageNo': '$page',
          'numOfRows': '500',
        });
        final r = await c.get(uri).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) throw Exception('회수 정보 ${r.statusCode}');
        final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
        final body = (d['body'] ?? (d['response'] as Map?)?['body']) as Map? ?? const {};
        var items = body['items'];
        if (items is Map) items = items['item'];
        if (items is Map) items = [items];
        final list = (items as List? ?? const []);
        for (final e in list) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from((e['item'] ?? e) as Map);
          final rc = Recall.fromApi(m);
          if (rc != null) all.add(rc);
        }
        final total = int.tryParse('${body['totalCount'] ?? 0}') ?? 0;
        if (list.isEmpty || page * 500 >= total) break;
      }
      if (all.isNotEmpty) {
        await p?.setString(_prefKey,
            jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'i': all.map((e) => e.toJson()).toList()}));
        return _mem = all;
      }
    } catch (_) {}
    return saved ?? const [];
  }
}

String recallDateLabel(DateTime? d) =>
    d == null ? '' : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

/// 회수 안내 문장 (쉬운 말로)
String recallAdvice(Recall r) =>
    '${r.forced ? '식약처가 회수를 명령한' : '제조사가 스스로 회수하는'} 약이에요'
    '${r.reason.isEmpty ? '' : ' (사유: ${r.reason})'}. '
    '회수는 보통 특정 제조번호만 해당돼요. 집에 남은 약이 있으면 먹거나 바르지 말고 약국에 가져가 '
    '회수 대상인지 확인하세요.';

/// 회수 안내에 쓸 기록 이름: 날짜에 연도까지 ("6월 3일 처방" → "2026년 6월 3일 처방")
String recallRecordLabel(MedRecord r) {
  final t = r.title.trim();
  if (RegExp(r'^\d{1,2}월').hasMatch(t)) return '${r.createdAt.year}년 $t';
  return '$t (${recallDateLabel(r.createdAt)})';
}

/// 주사제(병원에서 맞는 약)인지: "세프트리악손주1g", "오메프라졸주", "엔에스주사액", "○○앰플" 등
bool isInjection(String name) {
  final n = name.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'[(\[（].*$'), '');
  return RegExp(r'(주사|앰플|앰풀|바이알|주$|주\d)').hasMatch(n);
}

/// 이미 맞은 주사가 회수됐을 때 안내
String injectedRecallAdvice(Recall r) =>
    '병원에서 이미 맞은 주사라 따로 반납하거나 할 일은 없어요'
    '${r.reason.isEmpty ? '' : ' (회수 사유: ${r.reason})'}. '
    '맞은 뒤 평소와 다른 증상이 있었다면 진료받은 병원에 알려주세요.';
