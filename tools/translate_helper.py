#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
translate_helper.py — 能力文字補翻的固定流程工具

把先前踩過的坑寫成自動檢查，避免每個系列重犯：
  * 數字集合必須一致（3000 不能翻成 3500、「1番上」的 1 不能吃掉）
  * 【】標記數量必須一致（【レスト】→【橫置】漏掉會被 translate.py 退回）
  * 《》特徵必須原樣保留（traits 不翻譯，《音楽》就是《音楽》）
  * 譯文不得殘留假名（《》與「」內除外，那是專有名詞）

用法：
  python3 translate_helper.py dump  <key> [start] [count]   # 列出未翻譯的文字
  python3 translate_helper.py check <key> <譯文.json>        # 只驗證不寫檔
  python3 translate_helper.py apply <key> <譯文.json>        # 驗證並產生覆寫檔
  python3 translate_helper.py names <key>                   # 交叉驗證角色譯名
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

KANA = re.compile("[぀-ゟ゠-ヺー-ヿ]")
NUM = re.compile(r"\d+")
MARKER = re.compile(r"【[^】]*】")
TRAIT = re.compile(r"《[^》]*》")


def load(key):
    raw = json.load(open(f"{HERE}/sets/{key}_raw.json", encoding="utf-8"))
    cards = json.load(open(f"{HERE}/sets/{key}_cards.json", encoding="utf-8"))
    return raw, cards


def pending(key):
    """尚未翻譯的獨特能力文字，依卡號排序"""
    _, cards = load(key)
    seen, out = set(), []
    for c in cards["cards"]:
        jp, zh = c["text_jp"], c.get("text_zh", c["text_jp"])
        if jp and jp == zh and KANA.search(jp) and jp not in seen:
            seen.add(jp)
            out.append((c["id"], jp))
    return out


def cmd_dump(key, start=0, count=None):
    items = pending(key)
    start = int(start)
    end = len(items) if count is None else start + int(count)
    for cid, jp in items[start:end]:
        print(f"=== {cid} ===")
        print(jp)
        print()
    print(f"--- 顯示 {start}~{min(end, len(items))}，本系列共 {len(items)} 則未翻譯 ---",
          file=sys.stderr)


def verify(trans):
    """回傳 (問題清單)。空 = 全部通過。"""
    problems = []
    for jp, zh in trans.items():
        tag = jp[:34].replace("\n", " ")
        if not zh.strip():
            problems.append(f"[空譯文] {tag}")
            continue
        if sorted(NUM.findall(jp)) != sorted(NUM.findall(zh)):
            problems.append(f"[數字不符] {tag}\n    jp={NUM.findall(jp)}\n    zh={NUM.findall(zh)}")
        if len(MARKER.findall(jp)) != len(MARKER.findall(zh)):
            problems.append(f"[標記數不符] {tag}\n    jp={MARKER.findall(jp)}\n    zh={MARKER.findall(zh)}")
        if TRAIT.findall(jp) != TRAIT.findall(zh):
            problems.append(f"[特徵不符] {tag}\n    jp={TRAIT.findall(jp)}\n    zh={TRAIT.findall(zh)}")
        # 《》特徵與「」卡名可留日文，其餘不該有假名
        stripped = re.sub(r"《[^》]*》", "", re.sub(r"「[^」]*」", "", zh))
        residue = KANA.findall(stripped)
        if residue:
            problems.append(f"[殘留假名] {tag}\n    {''.join(residue[:12])}")
    return problems


def cmd_names(key):
    """交叉驗證：日文卡名含某角色時，中文卡名就該出現對應譯名。

    literal 覆寫（names）是逐條寫死的，改角色字典時很容易漏掉它們——
    賽馬娘就發生過兩隻馬的譯名互換卻只改了字典的情況。
    """
    extra = json.load(open(f"{HERE}/translations/names_extra.json", encoding="utf-8"))
    chars = extra.get("characters_by_set", {}).get(key, {})
    if not chars:
        print(f"{key} 沒有專屬角色字典，略過")
        return 0
    cards = json.load(open(f"{HERE}/sets/{key}_cards.json", encoding="utf-8"))["cards"]
    bad, seen = [], set()
    for c in cards:
        jp, zh = c["name_jp"], c["name_zh"]
        if zh == jp or jp in seen:
            continue
        seen.add(jp)
        # 取最長匹配，避免アグネスタキオン被アグネス…之類的短鍵搶走
        hit = max((k for k in chars if k in jp), key=len, default=None)
        if hit and chars[hit] not in zh:
            bad.append((c["id"], jp, zh, hit, chars[hit]))
    for cid, jp, zh, k, want in bad:
        print(f"  {cid:16} {jp[:26]:28} -> {zh:24} 應含「{want}」({k})")
    print(f"{key}：{len(bad)} 張角色名對不上"
          f"（部分可能是誤報，例如角色名同時是普通名詞）")
    return 1 if bad else 0


def cmd_check(key, path):
    trans = json.load(open(path, encoding="utf-8"))
    todo = {jp for _, jp in pending(key)}
    unknown = [k for k in trans if k not in todo]
    problems = verify(trans)
    for p in problems:
        print(p)
    if unknown:
        print(f"[不在待翻清單] {len(unknown)} 則（可能複製時被改動）")
        for k in unknown[:3]:
            print("   ", k[:60].replace("\n", " "))
    print(f"\n{len(trans)} 則譯文，{len(problems)} 個結構問題，"
          f"{len(unknown)} 則對不上原文；本系列還剩 {len(todo)} 則未翻譯")
    return 1 if (problems or unknown) else 0


def cmd_apply(key, path):
    if cmd_check(key, path) != 0:
        print("\n有問題，未寫檔。", file=sys.stderr)
        return 1
    trans = json.load(open(path, encoding="utf-8"))
    raw, _ = load(key)
    out_path = f"{HERE}/translations/texts_{key}_extra.json"
    existing = {}
    if os.path.exists(out_path):
        existing = json.load(open(out_path, encoding="utf-8"))
    added = 0
    for c in raw["cards"]:
        if c["text_jp"] in trans:
            if c["id"] not in existing:
                added += 1
            existing[c["id"]] = trans[c["text_jp"]]
    json.dump(existing, open(out_path, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"寫入 {out_path}：新增 {added} 張，共 {len(existing)} 張")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    cmd, key = sys.argv[1], sys.argv[2]
    if cmd == "dump":
        cmd_dump(key, *sys.argv[3:])
    elif cmd == "check":
        sys.exit(cmd_check(key, sys.argv[3]))
    elif cmd == "apply":
        sys.exit(cmd_apply(key, sys.argv[3]))
    elif cmd == "names":
        sys.exit(cmd_names(key))
    else:
        print(__doc__)
        sys.exit(2)
