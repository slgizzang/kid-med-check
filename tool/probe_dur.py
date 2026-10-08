import json, os, urllib.parse, urllib.request, urllib.error
key = os.environ["DUR_API_KEY"]
for svc in ["DURIrdntInfoService03", "DURIrdntInfoService02", "DURIrdntInfoService01"]:
    for op in ["getCpctyAtentInfoList", "getMdctnPdAtentInfoList"]:
        for suf in ["03", "02", "01", ""]:
            q = {"serviceKey": key, "type": "json", "numOfRows": 1, "pageNo": 1}
            url = f"https://apis.data.go.kr/1471000/{svc}/{op}{suf}?" + urllib.parse.urlencode(q)
            try:
                raw = urllib.request.urlopen(url, timeout=20).read().decode("utf-8", "replace")
                print(f"== {svc}/{op}{suf} OK", raw[:1500])
            except urllib.error.HTTPError as e:
                print(f"== {svc}/{op}{suf} {e.code}", e.read()[:150])
            except Exception as e:
                print(f"== {svc}/{op}{suf} fail {e}")
