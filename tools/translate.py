#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
translate.py — 階段一 M2：三層翻譯管線 raw_cards.json → brd_cards.json

第一層：術語表（glossary.json）— 功能性術語的權威來源，供驗證與 LLM prompt 使用
第二層：譯文來源，二擇一：
  a) translations/ 目錄內的人工／預先產出譯文（names.json + texts_*.json）
  b) --api：呼叫 Claude API 批次翻譯（需 ANTHROPIC_API_KEY；供未來擴充其他彈使用）
第三層：自動化驗證（validate() 內建執行；validate.py 可單獨重跑並輸出 review.html）

用法：
  python3 translate.py                          # 使用 translations/ 產出 brd_cards.json
  python3 translate.py --api                    # 未提供譯文的卡片改走 Claude API
"""
import argparse
import glob
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
KANA = re.compile(r"[぀-ゟ゠-ヿー]")
NUM = re.compile(r"\d+")
MARKER = re.compile(r"【[^】]*】")
TRAIT_REF = re.compile(r"《[^》]*》")


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_translations(only=None):
    """only=檔名清單（不含路徑）時只載入這些；None 表示全部。"""
    names, traits, texts = {}, {}, {}
    paths = sorted(glob.glob(os.path.join(HERE, "translations", "*.json")))
    if only:
        paths = [p for p in paths if os.path.basename(p) in only]
    for path in paths:
        data = load_json(path)
        names.update(data.get("names", {}))
        traits.update(data.get("traits", {}))
        for k, v in data.items():
            if k.startswith("BRD/") or re.match(r"^[A-Z]+/", k):
                texts[k] = v
    return names, traits, texts


def call_claude_api(glossary, batch):
    """第二層 b：Claude API 批次翻譯（未提供譯文時的備援路徑）。"""
    try:
        import urllib.request
        api_key = os.environ["ANTHROPIC_API_KEY"]
    except KeyError:
        raise SystemExit("需要 ANTHROPIC_API_KEY 環境變數才能使用 --api")
    glossary_str = json.dumps(glossary, ensure_ascii=False)
    system = (
        "你是 Weiß Schwarz 卡片翻譯引擎。將日文卡片文字翻譯為繁體中文（台灣用語）。\n"
        "硬性規則：1) 嚴格使用下列術語表的譯名，不得自創。2) 所有數字、卡號、【】標記、"
        "《》特徵、「」卡名原樣保留結構。3) 成本用〔 〕包住。4) 巢狀能力用『』。"
        "5) 保留被動語態（置かれた時→被放置到…時）。6) あなた→你、相手→對手。\n"
        f"術語表：{glossary_str}\n"
        "輸入為 JSON 陣列 [{id, name_jp, text_jp}]，回傳同長度 JSON 陣列 "
        "[{id, name_zh, text_zh}]，只回傳 JSON。"
    )
    body = json.dumps({
        "model": "claude-sonnet-5",
        "max_tokens": 8000,
        "temperature": 0,
        "system": system,
        "messages": [{"role": "user",
                      "content": json.dumps(batch, ensure_ascii=False)}],
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={"x-api-key": api_key, "anthropic-version": "2023-06-01",
                 "content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        out = json.loads(resp.read().decode("utf-8"))
    return json.loads(out["content"][0]["text"])


# ── 第三層：自動化驗證 ──────────────────────────

def check_card(card, glossary):
    """回傳問題清單（空 = 通過）。"""
    problems = []
    jp, zh = card["text_jp"], card["text_zh"]
    if not jp and not zh:
        return problems
    if not zh:
        problems.append("缺少譯文")
        return problems
    if zh == jp:
        return problems  # 未翻譯直通（多作品擴充：先收錄日文，翻譯後補）
    # 1. 數字集合必須一致（防止 3000 → 3500）
    if sorted(NUM.findall(jp)) != sorted(NUM.findall(zh)):
        problems.append(f"數字不一致 jp={NUM.findall(jp)} zh={NUM.findall(zh)}")
    # 2. 【】標記數量一致
    if len(MARKER.findall(jp)) != len(MARKER.findall(zh)):
        problems.append(f"【】數量不一致 {len(MARKER.findall(jp))} vs {len(MARKER.findall(zh))}")
    # 3. 《》特徵數量一致
    if len(TRAIT_REF.findall(jp)) != len(TRAIT_REF.findall(zh)):
        problems.append("《》數量不一致")
    # 4. 譯文不得殘留假名（《》特徵與「」卡名屬專有名詞，可保留日文）
    stripped = re.sub(r"《[^》]*》", "《》", re.sub(r"「[^」]*」", "「」", zh))
    residue = KANA.findall(stripped)
    if residue:
        problems.append(f"殘留假名：{''.join(residue[:10])}")
    # 5. 術語一致性：原文含特定術語時譯文必須用指定譯名、不得用舊譯
    required = {"控え室": "休息室", "山札": "牌組", "ストック": "能量區", "クロック": "傷害區"}
    for jp_term, zh_term in required.items():
        if jp_term in jp:
            if zh_term not in zh:
                problems.append(f"術語缺漏：{jp_term} 應譯為 {zh_term}")
            for bad in glossary.get("forbidden_translations", {}).get(jp_term, []):
                if bad in zh:
                    problems.append(f"出現舊譯：{bad}")
    # 6. 長度比例 40%~250%
    if jp and not (0.4 * len(jp) <= len(zh) <= 2.5 * len(jp)):
        problems.append(f"長度異常 jp={len(jp)} zh={len(zh)}")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=os.path.join(HERE, "raw_cards.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "brd_cards.json"))
    ap.add_argument("--api", action="store_true",
                    help="未提供譯文的卡片改走 Claude API 批次翻譯")
    ap.add_argument("--tr", default=None,
                    help="只使用指定譯文檔（逗號分隔，如 auto_nik.json）")
    ap.add_argument("--mark-reviewed", action="store_true",
                    help="人工校對完成後執行：translation_status 全部改為 reviewed")
    args = ap.parse_args()

    raw = load_json(args.raw)
    glossary = load_json(os.path.join(HERE, "glossary.json"))
    only = [x.strip() for x in args.tr.split(",")] if args.tr else None
    names, traits, texts_by_id = load_translations(only)

    # 依 text_jp 完全一致建立譯文索引（同文重複收錄自動共用）
    text_map = {}
    for cid, zh in texts_by_id.items():
        card = next((c for c in raw["cards"] if c["id"] == cid), None)
        if card is None:
            continue   # 其他作品的譯文 key，略過
        text_map[card["text_jp"]] = zh

    # 校對頁匯出的結果（review.html →「匯出校對結果」→ 放到 tools/）
    review_path = os.path.join(HERE, "review_result.json")
    review = load_json(review_path) if os.path.exists(review_path) else {}
    # 打 ✓ 的卡以（卡名, 文字）為單位擴散到重複收錄
    approved_pairs = set()
    for c in raw["cards"]:
        if review.get(c["id"], {}).get("status") == "ok":
            approved_pairs.add((c["name_jp"], c["text_jp"]))

    missing = []
    cards_out = []
    for c in raw["cards"]:
        name_zh = names.get(c["name_jp"])
        text_zh = text_map.get(c["text_jp"])
        if name_zh is None or (c["text_jp"] and text_zh is None):
            missing.append(c)
            name_zh = name_zh or c["name_jp"]
            text_zh = text_zh if text_zh is not None else c["text_jp"]
        card = dict(c)
        card["name_zh"] = name_zh
        card["traits_zh"] = [traits.get(t, t) for t in c["traits_jp"]]
        card["text_zh"] = text_zh or ""
        card["text_lines_jp"] = [l for l in c["text_jp"].split("\n") if l.strip()]
        card["text_lines_zh"] = [l for l in card["text_zh"].split("\n") if l.strip()]
        approved = (c["name_jp"], c["text_jp"]) in approved_pairs
        card["translation_status"] = ("reviewed"
                                      if args.mark_reviewed or approved else "machine")
        cards_out.append(card)

    if missing and args.api:
        print(f"{len(missing)} 張卡走 Claude API 翻譯…", file=sys.stderr)
        for i in range(0, len(missing), 15):
            batch = [{"id": c["id"], "name_jp": c["name_jp"], "text_jp": c["text_jp"]}
                     for c in missing[i:i + 15]]
            for r in call_claude_api(glossary, batch):
                for card in cards_out:
                    if card["id"] == r["id"]:
                        card["name_zh"] = r["name_zh"]
                        card["text_zh"] = r["text_zh"]
                        card["text_lines_zh"] = [l for l in r["text_zh"].split("\n") if l.strip()]
            time.sleep(1.5)
    elif missing:
        print(f"警告：{len(missing)} 張卡缺譯文（沿用日文）："
              f"{[c['id'] for c in missing[:10]]}", file=sys.stderr)

    # 第三層驗證：不通過就把譯文退回日文，寧可不翻也不出錯
    failed = reverted = 0
    for card in cards_out:
        problems = check_card(card, glossary)
        if problems:
            failed += 1
            print(f"✗ {card['id']}: {'; '.join(problems)}", file=sys.stderr)
            if card["text_zh"] != card["text_jp"]:
                card["text_zh"] = card["text_jp"]
                card["text_lines_zh"] = card["text_lines_jp"]
                reverted += 1
    if reverted:
        print(f"（{reverted} 張驗證未過，譯文已退回日文）", file=sys.stderr)

    out = {"meta": dict(raw["meta"]), "cards": cards_out}
    out["meta"]["generated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S+08:00")
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"完成：{len(cards_out)} 張卡 → {args.out}"
          f"（驗證未通過 {failed} 張）", file=sys.stderr)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
