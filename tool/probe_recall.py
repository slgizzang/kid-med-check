import json, os, urllib.parse, urllib.request, urllib.error
key = os.environ["DUR_API_KEY"]
base = "https://apis.data.go.kr/1471000/MdcinRtrvlSleStpgeInfoService04/getMdcinRtrvlSleStpgelList03"
for extra in [{}, {"pageNo": 2}, {"Prduct": "챔프"}, {"prduct": "챔프"}, {"item_name": "챔프"}]:
    q = {"serviceKey": key, "type": "json", "numOfRows": 3, "pageNo": 1}
    q.update(extra)
    try:
        raw = urllib.request.urlopen(base + "?" + urllib.parse.urlencode(q), timeout=25).read().decode("utf-8", "replace")
        try:
            d = json.loads(raw)
            b = d.get("body") or {}
            items = b.get("items") or []
            print("==", extra, "total", b.get("totalCount"))
            print(json.dumps(items[:3], ensure_ascii=False, indent=1)[:4000])
        except Exception:
            print("==", extra, raw[:1500])
    except urllib.error.HTTPError as e:
        print("==", extra, e.code, e.read()[:300])
