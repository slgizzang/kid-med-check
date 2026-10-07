import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../logic/dur_api.dart';
import '../logic/storage.dart';
import 'theme.dart';

/// 병원·약국을 이름으로 검색해 고른다 (심평원 병원·약국 정보).
/// 검색이 안 되면 입력한 이름 그대로 쓸 수 있다. 취소하면 null.
Future<PlaceHit?> showPlaceSheet(BuildContext context,
    {required bool pharmacy, String initial = ''}) {
  return showModalBottomSheet<PlaceHit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => _PlaceSheet(pharmacy: pharmacy, initial: initial),
  );
}

class _PlaceSheet extends StatefulWidget {
  const _PlaceSheet({required this.pharmacy, required this.initial});

  final bool pharmacy;
  final String initial;

  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

/// 이번 실행 중 한 번 얻은 대략적 위치 (위도, 경도)
(double, double)? _lastPos;

/// 대략적 위치. 권한이 없거나 꺼져 있으면 null (이름 검색만 함).
Future<(double, double)?> _roughPosition() async {
  if (_lastPos != null) return _lastPos;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }
    final last = await Geolocator.getLastKnownPosition();
    final p = last ??
        await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
    _lastPos = (p.latitude, p.longitude);
    return _lastPos;
  } catch (_) {
    return null;
  }
}

class _PlaceSheetState extends State<_PlaceSheet> {
  (double, double)? _pos;
  bool _locating = true;
  late final _ctl = TextEditingController(text: widget.initial);
  Timer? _debounce;
  List<PlaceHit> _hits = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  String get _what => widget.pharmacy ? '약국' : '병원';

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// 위치를 먼저 얻고(가까운 순 정렬), 입력된 이름이 있으면 그 이름으로, 없으면 주변을 찾는다.
  Future<void> _init() async {
    final pos = await _roughPosition();
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _locating = false;
    });
    await _search(_ctl.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
  }

  Future<void> _search(String q) async {
    final my = ++_seq;
    if (q.trim().length < 2 && _pos == null) {
      setState(() {
        _hits = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = DurApi(await AppStorage.apiKey());
      final hits = await api.searchPlaces(q,
          pharmacy: widget.pharmacy, lat: _pos?.$1, lon: _pos?.$2);
      if (!mounted || my != _seq) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _hits = const [];
        _loading = false;
        _error = '$_what 검색이 지금은 안 돼요. 아래에서 입력한 이름 그대로 쓸 수 있어요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final typed = _ctl.text.trim();
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: KText(widget.pharmacy ? '약을 지은 약국' : '진료받은 병원',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: KText('이름 일부만 입력해도 비슷한 $_what을 가까운 순으로 보여줘요.',
                style: const TextStyle(fontSize: 13, color: AppColors.sub)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctl,
              autofocus: widget.initial.isEmpty,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: widget.pharmacy ? '예: 온누리약국' : '예: 써니이비인후과',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading || _locating) const LinearProgressIndicator(minHeight: 2),
          if (!_locating && typed.length < 2 && _pos != null && _hits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: KText('내 주변 $_what · 가까운 순',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sub)),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: KText(_error!,
                        style: const TextStyle(fontSize: 13, color: AppColors.sub)),
                  ),
                for (final h in _hits)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: Icon(
                        widget.pharmacy
                            ? Icons.local_pharmacy_outlined
                            : Icons.local_hospital_outlined,
                        color: AppColors.primary),
                    title: KText(h.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppColors.ink)),
                    subtitle: KText(
                        [h.distanceLabel, h.kind, h.addr].where((x) => x.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.sub)),
                    onTap: () => Navigator.pop(context, h),
                  ),
                if (!_loading && _error == null && typed.length >= 2 && _hits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: KText('"$typed"(으)로 찾은 $_what이 없어요.',
                        style: const TextStyle(fontSize: 13, color: AppColors.sub)),
                  ),
                if (typed.length >= 2)
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.edit_outlined, color: AppColors.sub),
                    title: KText('"$typed" 그대로 쓰기',
                        style: const TextStyle(color: AppColors.ink)),
                    onTap: () => Navigator.pop(context, PlaceHit(name: typed)),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
