#!/usr/bin/env python3
"""卡表健檢：確認 Resources/ 底下的卡表結構完好。

壞掉的卡表推上線之後，手機下載時會在 DataUpdater 的驗證關卡被擋下來，
結果是「更新一直失敗」而不是「App 壞掉」——但那時候已經來不及，
使用者得等你發現並修好。這支腳本把同樣的檢查提前到 push 之前。

CI 會自動跑（.github/workflows/card-data-check.yml），本機也可以直接執行：

    python3 tools/check_cards.py
"""

import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

REQUIRED_META = ["title_code", "title_name_jp", "title_name_zh",
                 "card_count", "data_version"]


def check_set(path, problems):
    name = os.path.basename(path)

    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as exc:
        problems.append(f"{name}：讀不開或不是合法 JSON（{exc}）")
        return None

    meta = data.get("meta")
    cards = data.get("cards")
    if not isinstance(meta, dict) or not isinstance(cards, list):
        problems.append(f"{name}：缺少 meta 或 cards")
        return None

    for key in REQUIRED_META:
        if key not in meta:
            problems.append(f"{name}：meta 缺少 {key}")

    # App 端逐部作品比對版本號，非正整數會讓比對邏輯失去意義
    version = meta.get("data_version")
    if not isinstance(version, int) or version < 1:
        problems.append(f"{name}：data_version 必須是 >= 1 的整數（目前 {version!r}）")

    if meta.get("card_count") != len(cards):
        problems.append(f"{name}：card_count {meta.get('card_count')} "
                        f"與實際 {len(cards)} 張不符")

    if not cards:
        problems.append(f"{name}：沒有任何卡片（App 會拒絕安裝這種卡表）")

    seen = set()
    for card in cards:
        cid = card.get("id")
        if not cid:
            problems.append(f"{name}：有卡片沒有 id")
            continue
        if cid in seen:
            problems.append(f"{name}：卡號重複 {cid}")
        seen.add(cid)
        # defaultPrinting 直接取 printings[0]，空陣列會在 App 端 index out of range
        if not card.get("printings"):
            problems.append(f"{name}：{cid} 沒有任何刷版")

    return meta


def check_manifest(manifest_path, resources, metas, problems):
    if not manifest_path or not os.path.exists(manifest_path):
        return  # 還沒產生過，不算錯

    try:
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
    except (OSError, ValueError) as exc:
        problems.append(f"manifest.json：讀不開或不是合法 JSON（{exc}）")
        return

    if manifest.get("schema_version") != 1:
        problems.append("manifest.json：schema_version 應為 1")

    # 版本號刻意不比對——manifest 由 CI 在同一次 push 之後才重新產生，
    # 這時候本來就會落後一個版本，比了只會得到假警報
    for entry in manifest.get("sets", []):
        target = os.path.join(resources, entry.get("file", ""))
        if not os.path.exists(target):
            problems.append(f"manifest：指向不存在的檔案 {entry.get('file')}")
        if entry.get("title_code") not in metas:
            problems.append(f"manifest：{entry.get('title_code')} "
                            "沒有對應的卡表")


def main():
    parser = argparse.ArgumentParser(description="卡表結構健檢")
    parser.add_argument("--resources",
                        default=os.path.join(ROOT, "WSDeckBuilder", "Resources"),
                        help="卡表所在目錄")
    parser.add_argument("--manifest",
                        default=os.path.join(ROOT, "data", "manifest.json"),
                        help="要一併檢查的 manifest（不存在就略過）")
    args = parser.parse_args()

    paths = sorted(glob.glob(os.path.join(args.resources, "*_cards.json")))
    if not paths:
        print(f"在 {args.resources} 找不到任何 *_cards.json", file=sys.stderr)
        sys.exit(1)

    problems = []
    metas = {}
    total = 0
    for path in paths:
        meta = check_set(path, problems)
        if meta:
            metas[meta.get("title_code")] = meta
            total += meta.get("card_count", 0)
            print(f"  {meta.get('title_code', '?'):<10} "
                  f"v{meta.get('data_version', '?')}  "
                  f"{meta.get('card_count', '?')} 張")

    check_manifest(args.manifest, args.resources, metas, problems)

    print(f"\n{len(paths)} 部作品，共 {total} 張卡")
    if problems:
        print(f"\n發現 {len(problems)} 個問題：", file=sys.stderr)
        for p in problems:
            print(f"  ✗ {p}", file=sys.stderr)
        sys.exit(1)
    print("全部通過")


if __name__ == "__main__":
    main()
