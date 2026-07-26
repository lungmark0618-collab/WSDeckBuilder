#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate.py — 階段一 M3：重跑自動化驗證＋產出日中對照校對頁 review.html

用法：
  python3 validate.py            # 驗證 brd_cards.json 並產出 review.html
"""
import html
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from translate import check_card, load_json  # noqa: E402

STATUS_LABEL = {"machine": "機翻", "reviewed": "已校對", "manual": "人工"}

PAGE = """<!DOCTYPE html>
<html lang="zh-Hant"><head><meta charset="utf-8">
<title>BRD/W139 翻譯校對</title>
<style>
body {{ font-family: -apple-system, "PingFang TC", sans-serif; margin: 2rem; background:#f5f5f7; }}
.card {{ background:#fff; border-radius:10px; padding:1rem 1.2rem; margin-bottom:1rem;
        box-shadow:0 1px 3px rgba(0,0,0,.1); }}
.card.warn {{ border-left: 4px solid #d33; }}
.hd {{ display:flex; gap:.8rem; align-items:baseline; flex-wrap:wrap; }}
.id {{ font-family:ui-monospace,monospace; color:#666; }}
.status {{ font-size:.75rem; padding:.1rem .5rem; border-radius:1rem; background:#ffe6b3; }}
.status.reviewed {{ background:#c9f0c9; }}
.cols {{ display:grid; grid-template-columns:1fr 1fr; gap:1rem; margin-top:.6rem; }}
.cols pre {{ white-space:pre-wrap; margin:0; font-family:inherit; font-size:.9rem;
            line-height:1.6; background:#fafafa; padding:.6rem; border-radius:6px; }}
.problems {{ color:#c00; font-size:.85rem; margin-top:.4rem; }}
h1 small {{ color:#888; font-weight:normal; }}
</style></head><body>
<h1>BRD/W139 棕色塵埃2 — 翻譯校對 <small>{count} 張・未通過 {failed} 張</small></h1>
{rows}
</body></html>"""

ROW = """<div class="card{warn}">
 <div class="hd"><b>{name_jp}</b> ⇄ <b>{name_zh}</b>
  <span class="id">{id}</span><span>{meta}</span>
  <span class="status {status}">{status_label}</span></div>
 <div class="cols"><pre>{jp}</pre><pre>{zh}</pre></div>
 {problems}
</div>"""


def main():
    data = load_json(os.path.join(HERE, "brd_cards.json"))
    glossary = load_json(os.path.join(HERE, "glossary.json"))
    rows, failed = [], 0
    for c in data["cards"]:
        problems = check_card(c, glossary)
        if problems:
            failed += 1
        meta = f"Lv{c['level']}/Co{c['cost']}/Pw{c['power']}" \
            if c["card_type"] == "character" else c["card_type"]
        rows.append(ROW.format(
            warn=" warn" if problems else "",
            name_jp=html.escape(c["name_jp"]), name_zh=html.escape(c["name_zh"]),
            id=html.escape(c["id"]), meta=meta,
            status=c["translation_status"],
            status_label=STATUS_LABEL.get(c["translation_status"], "?"),
            jp=html.escape(c["text_jp"] or "（無能力文字）"),
            zh=html.escape(c["text_zh"] or "（無能力文字）"),
            problems=f'<div class="problems">⚠ {"; ".join(problems)}</div>' if problems else ""))
    out = os.path.join(HERE, "review.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(PAGE.format(count=len(data["cards"]), failed=failed, rows="\n".join(rows)))
    print(f"驗證：{len(data['cards'])} 張、未通過 {failed} 張 → {out}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
