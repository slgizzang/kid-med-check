import json, os, urllib.parse, urllib.request, urllib.error
key = os.environ["DUR_API_KEY"]
svc = "https://apis.data.go.kr/1471000/MdcinRtrvlSleStpgeInfoService05/"
ok = None
for op in ["getMdcinRtrvlSleStpgelList05", "getMdcinRtrvlSleStpgeList05", "getMdcinRtrvlSleStpgelList04",
           "getMdcinRtrvlSleStpgelList03", "getMdcinRtrvlSleStpgelList", "getMdcinRtrvlSleStpgeList"]:
    q = {"serviceKey": key, "type": "json", "numOfRows": 3, "pageNo": 1}
    try:
        raw = urllib.request.urlopen(svc + op + "?" + urllib.parse.urlencode(q), timeout=25).read().decode("utf-8", "replace")
        print("== OK", op, raw[:4000])
        ok = op
        break
    except urllib.error.HTTPError as e:
        b = e.read()[:300].decode("utf-8", "replace")
        print("==", e.code, op, "NO_SERVICE" if "NO_OPENAPI" in b else b[:200])
if ok:
    for extra in [{"Prduct": "챔프"}, {"prduct": "챔프"}, {"PRDUCT": "챔프"}]:
        q = {"serviceKey": key, "type": "json", "numOfRows": 2, "pageNo": 1, **extra}
        try:
            raw = urllib.request.urlopen(svc + ok + "?" + urllib.parse.urlencode(q), timeout=25).read().decode("utf-8", "replace")
            d = json.loads(raw); b = d.get("body") or {}
            print("== filter", extra, "total", b.get("totalCount"), json.dumps(b.get("items"), ensure_ascii=False)[:600])
        except Exception as e:
            print("== filter", extra, e)
