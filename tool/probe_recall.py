import json, os, urllib.parse, urllib.request, urllib.error
key = os.environ["DUR_API_KEY"]
cands = []
for v in ["04", "03", "02", "01", ""]:
    for op in ["getMdcinRtrvlSleStpgelList", "getMdcinRtrvlSleStpgeList", "getMdcinRtrvlSleStpgelList03", "getMdcinRtrvlSleStpgeList03",
               "getMdcinRtrvlSleStpgelList02", "getMdcinRtrvlSleStpgelList01"]:
        cands.append(f"MdcinRtrvlSleStpgeInfoService{v}/{op}")
seen = set()
for c in cands:
    if c in seen: continue
    seen.add(c)
    q = {"serviceKey": key, "type": "json", "numOfRows": 2, "pageNo": 1}
    url = f"https://apis.data.go.kr/1471000/{c}?" + urllib.parse.urlencode(q)
    try:
        raw = urllib.request.urlopen(url, timeout=20).read().decode("utf-8", "replace")
        print("== OK", c, raw[:2500])
    except urllib.error.HTTPError as e:
        b = e.read()[:400].decode("utf-8", "replace")
        tag = "NO_SERVICE" if "NO_OPENAPI_SERVICE" in b else ("NOT_REGISTERED" if "REGISTERED" in b or "FORBIDDEN" in b else b[:160])
        print("==", e.code, c, tag)
    except Exception as e:
        print("== fail", c, e)
