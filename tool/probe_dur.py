import json, os, urllib.parse, urllib.request
key = os.environ["DUR_API_KEY"]
base = "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/"
ops = ["getCpctyAtentInfoList03", "getMdctnPdAtentInfoList03"]
for op in ops:
    for name in ["타이레놀", "세토펜", ""]:
        q = {"serviceKey": key, "type": "json", "numOfRows": 3, "pageNo": 1}
        if name:
            q["itemName"] = name
        try:
            d = json.loads(urllib.request.urlopen(base + op + "?" + urllib.parse.urlencode(q), timeout=20).read())
            b = d.get("body") or d.get("response", {}).get("body", {})
            items = b.get("items") or []
            if isinstance(items, dict):
                items = items.get("item", [])
            if isinstance(items, dict):
                items = [items]
            print(f"== {op} [{name}] total={b.get('totalCount')}")
            for it in items[:2]:
                it = it.get("item", it)
                print("  ", json.dumps(it, ensure_ascii=False, indent=1))
        except Exception as e:
            print(f"== {op} [{name}] fail {e}")
