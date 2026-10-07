"""CI에서 실제 식약처 DUR API를 한 번 호출해 키 동작 여부와 응답 형태를 기록한다.
키 값은 절대 출력하지 않는다."""
import json
import os
import urllib.parse
import urllib.request

key = os.environ.get("DUR_API_KEY", "")
out = []
if not key:
    out.append("API 점검: 인증키가 설정되지 않은 빌드입니다 (사용자가 설정에서 입력해야 함).")
else:
    base = "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getSpcifyAgrdeTabooInfoList03"
    for name in ["코대원", "정"]:
        q = urllib.parse.urlencode(
            {"serviceKey": key, "type": "json", "pageNo": 1, "numOfRows": 3, "itemName": name}
        )
        try:
            with urllib.request.urlopen(f"{base}?{q}", timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            try:
                d = json.loads(body)
                root = d.get("response", d)
                header = root.get("header", {})
                b = root.get("body", {})
                items = b.get("items", [])
                if isinstance(items, dict):
                    items = items.get("item", [])
                if isinstance(items, dict):
                    items = [items]
                items = [i.get("item", i) if isinstance(i, dict) else i for i in items]
                out.append(
                    f"[{name}] resultCode={header.get('resultCode')} totalCount={b.get('totalCount')}"
                )
                if items:
                    first = items[0]
                    out.append(f"  fields: {', '.join(first.keys())}")
                    for k in ("ITEM_NAME", "INGR_KOR_NAME", "PROHBT_CONTENT", "REMARK"):
                        if k in first:
                            out.append(f"  {k}: {str(first[k])[:120]}")
            except json.JSONDecodeError:
                out.append(f"[{name}] JSON 아님: {body[:300]}")
        except Exception as e:  # noqa: BLE001
            out.append(f"[{name}] 호출 실패: {type(e).__name__}: {str(e)[:200]}")

    extra = [
        ("e약은요", "https://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList", "타이레놀"),
        ("DUR품목", "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getDurPrdlstInfoList03", "세토펜"),
        ("병용금기", "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getUsjntTabooInfoList03", "코대원정"),
        ("임부금기", "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getPwnmTabooInfoList03", "코대원정"),
        ("병용금기2", "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getUsjntTabooInfoList03", "스포라녹스"),
        ("DUR품목-레어세", "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getDurPrdlstInfoList03", "레어세립"),
        ("DUR품목-날린", "https://apis.data.go.kr/1471000/DURPrdlstInfoService03/getDurPrdlstInfoList03", "날린패"),
    ]
    # 의약품 제품 허가정보 (DrugPrdtPrmsnInfoService08) - 오퍼레이션 이름 후보를 차례로 시도
    ops = ["getDrugPrdtPrmsnInq08", "getDrugPrdtPrmsnInq07", "getDrugPrdtPrmsnInq06",
           "getDrugPrdtPrmsnDtlInq07", "getDrugPrdtPrmsnDtlInq06", "getDrugPrdtPrmsnDtlInq05",
           "getDrugPrdtMcpnDtlInq08", "getDrugPrdtMcpnDtlInq07"]
    for op in ops:
        for pname, qname in [("item_name", "프리비투스"), ("item_name", "싱귤레어세립"), ("item_name", "레스날린")]:
            q = urllib.parse.urlencode({"serviceKey": key, "type": "json", "pageNo": 1, "numOfRows": 2, pname: qname})
            try:
                with urllib.request.urlopen(f"https://apis.data.go.kr/1471000/DrugPrdtPrmsnInfoService08/{op}?{q}", timeout=30) as r:
                    body = r.read().decode("utf-8", "replace")
                out.append(f"[허가08 {op} {qname}] " + " ".join(body.split())[:1200])
            except Exception as e:  # noqa: BLE001
                detail = ""
                if hasattr(e, "read"):
                    try:
                        detail = " ".join(e.read().decode("utf-8", "replace").split())[:160]
                    except Exception:  # noqa: BLE001
                        pass
                out.append(f"[허가08 {op} {qname}] 실패: {type(e).__name__} {detail}")
                break  # 오퍼레이션이 없으면 다른 이름으로 시도할 필요 없음

    for label, url, name in extra:
        q = urllib.parse.urlencode(
            {"serviceKey": key, "type": "json", "pageNo": 1, "numOfRows": 1, "itemName": name}
        )
        try:
            with urllib.request.urlopen(f"{url}?{q}", timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            try:
                d = json.loads(body)
                root = d.get("response", d)
                b = root.get("body", {})
                items = b.get("items", [])
                if isinstance(items, dict):
                    items = items.get("item", [])
                if isinstance(items, dict):
                    items = [items]
                out.append(f"[{label}:{name}] resultCode={root.get('header', {}).get('resultCode')} totalCount={b.get('totalCount')}")
                if items:
                    first = items[0]
                    out.append(f"  fields: {', '.join(first.keys())}")
                    out.append("  " + " | ".join(f"{k}={str(v)[:50]}" for k, v in first.items()))
            except json.JSONDecodeError:
                out.append(f"[{label}] JSON 아님: {body[:300]}")
        except Exception as e:  # noqa: BLE001
            out.append(f"[{label}] 호출 실패: {type(e).__name__}: {str(e)[:200]}")

    # DUR 성분정보: 성분별 특정연령대금기 (연령 기준 필드 확인용) - 서비스 이름 후보를 차례로 시도
    import urllib.error
    for svc, op in [("DURIrdntInfoService03", "getSpcifyAgrdeTabooInfoList02"),
                    ("DURIrdntInfoService03", "getUsjntTabooInfoList02")]:
        url = f"https://apis.data.go.kr/1471000/{svc}/{op}"
        q = urllib.parse.urlencode({"serviceKey": key, "type": "json", "pageNo": 1, "numOfRows": 3})
        try:
            with urllib.request.urlopen(f"{url}?{q}", timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
            try:
                d = json.loads(body)
                root = d.get("response", d)
                b2 = root.get("body", {})
                items = b2.get("items", [])
                if isinstance(items, dict):
                    items = items.get("item", [])
                if isinstance(items, dict):
                    items = [items]
                out.append(f"[DUR성분 {svc}/{op}] resultCode={root.get('header', {}).get('resultCode')} totalCount={b2.get('totalCount')}")
                for it in items[:3]:
                    it = it.get("item", it) if isinstance(it, dict) else it
                    out.append("  " + " | ".join(f"{k}={str(v)[:40]}" for k, v in it.items()))
            except json.JSONDecodeError:
                out.append(f"[DUR성분 {svc}] JSON 아님: {body[:200]}")
        except urllib.error.HTTPError as e:
            detail = " ".join(e.read().decode("utf-8", "replace").split())[:300] if hasattr(e, "read") else ""
            out.append(f"[DUR성분 {svc}] HTTP {e.code}: {detail}")
        except Exception as e:  # noqa: BLE001
            out.append(f"[DUR성분 {svc}] 호출 실패: {type(e).__name__}: {str(e)[:150]}")

    # 심평원 병원·약국 검색 (실손 청구에서 병원·약국 고르기) — 같은 인증키로 활용신청돼 있어야 한다
    for label, path, q in [
        ("심평원 병원", "B551182/hospInfoServicev2/getHospBasisList", "서울대학교병원"),
        ("심평원 약국", "B551182/pharmacyInfoService/getParmacyBasisList", "온누리약국"),
    ]:
        qs = urllib.parse.urlencode({"serviceKey": key, "_type": "json", "pageNo": 1, "numOfRows": 2, "yadmNm": q})
        try:
            with urllib.request.urlopen(f"https://apis.data.go.kr/{path}?{qs}", timeout=15) as r:
                body = r.read().decode("utf-8", "replace")
            out.append(f"[{label} {q}] " + " ".join(body.split())[:400])
        except Exception as e:  # noqa: BLE001
            detail = ""
            if hasattr(e, "read"):
                try:
                    detail = " ".join(e.read().decode("utf-8", "replace").split())[:200]
                except Exception:  # noqa: BLE001
                    pass
            out.append(f"[{label} {q}] 실패: {type(e).__name__} {detail}")

text = "\n".join(out).replace(key, "***") if key else "\n".join(out)
print(text)
with open("api_smoke.txt", "w", encoding="utf-8") as f:
    f.write(text + "\n")
