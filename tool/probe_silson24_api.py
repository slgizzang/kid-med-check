"""실손24 참여기관 검색 API를 브라우저 없이 부를 수 있는지 확인 (진단용)."""
import json
import urllib.request

BASE = "https://www.silson24.or.kr/cmm/api"
H = {"Content-Type": "application/json", "Accept": "application/json",
     "User-Agent": "Mozilla/5.0", "Referer": "https://www.silson24.or.kr/claim/web/serviceHospitalList",
     "Origin": "https://www.silson24.or.kr"}


def post(path, body):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers=H, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        return 0, repr(e)


def brief(txt):
    try:
        d = json.loads(txt)
        res = d.get("result")
        if isinstance(res, list):
            return f"{len(res)} items: " + " | ".join(
                f"{x.get('insttNm')}/{x.get('hospitalCd')}/svc={x.get('serviceEnabled')}/join={x.get('joinEnabled')}" for x in res[:6])
        return txt[:400]
    except Exception:  # noqa: BLE001
        return txt[:400]


cases = [
    ("keyword only, no loc", {"keyword": "서울아산병원", "servicedOnly": False, "hospitalType": "hospital",
                               "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False, "orderBy": "distance"}),
    ("keyword, servicedOnly", {"keyword": "강동성심병원", "servicedOnly": True, "hospitalType": "hospital",
                                "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False}),
    ("not joined clinic?", {"keyword": "써니이비인후과", "servicedOnly": False, "hospitalType": "hospital",
                             "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False}),
    ("pharmacy type", {"keyword": "온누리약국", "servicedOnly": False, "hospitalType": "pharmacy",
                        "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False}),
    ("pharmacy type2", {"keyword": "온누리약국", "servicedOnly": False, "hospitalType": "drugstore",
                         "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False}),
    ("pharmacy in hospital type", {"keyword": "온누리약국", "servicedOnly": False, "hospitalType": "hospital",
                                    "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False}),
    ("no type", {"keyword": "온누리약국", "servicedOnly": False,
                 "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False}),
    ("legal name", {"keyword": "재단법인아산사회복지재단서울아산병원", "servicedOnly": False, "hospitalType": "hospital",
                    "offset": {"offset": 0, "limit": 20}, "isCurrentLocation": False}),
]
for name, body in cases:
    for path in ["/v2/claim/getSearchHospitalsLocation", "/v2/claim/getSearchHospitals"]:
        st, txt = post(path, body)
        print(f"== {name} {path} -> {st}: {brief(txt)}")

# 페이지 스크립트에서 hospitalType 값 후보 찾기
try:
    html = urllib.request.urlopen(urllib.request.Request(
        "https://www.silson24.or.kr/claim/web/serviceHospitalList", headers={"User-Agent": "Mozilla/5.0"}), timeout=20).read().decode("utf-8", "replace")
    import re
    srcs = re.findall(r'src="([^"]+\.js)"', html)
    print("SCRIPTS", srcs[:20])
    for s in srcs:
        u = s if s.startswith("http") else "https://www.silson24.or.kr" + s
        js = urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=20).read().decode("utf-8", "replace")
        for m in re.finditer(r'hospitalType[^;]{0,160}', js):
            print("JS", s, m.group(0)[:200])
        for m in re.finditer(r'(pharm|drugstore|PHARM)[^;]{0,80}', js):
            print("JSP", s, m.group(0)[:120])
except Exception as e:  # noqa: BLE001
    print("SCRIPTFAIL", e)
