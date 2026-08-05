#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate.py — 階段一 M3：重跑自動化驗證＋產出互動式日中對照校對頁 review.html

校對頁功能：
  - 每張卡可打 ✓（沒問題）／✗（有問題）並寫備註，進度存在瀏覽器 localStorage
  - 「匯出校對結果」會下載 review_result.json；放到 tools/ 後執行
    translate.py 會自動把打 ✓ 的卡標為 reviewed（同名同文的重複收錄自動跟進）

用法：
  python3 validate.py            # 驗證 brd_cards.json 並產出 review.html
"""
import argparse
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
body { font-family: -apple-system, "PingFang TC", sans-serif; margin: 0; background:#f5f5f7; }
.topbar { position:sticky; top:0; z-index:10; background:#fffffff2; backdrop-filter:blur(8px);
          border-bottom:1px solid #ddd; padding:.7rem 2rem; display:flex; gap:1rem;
          align-items:center; flex-wrap:wrap; }
.topbar h1 { font-size:1rem; margin:0; }
.progress { font-variant-numeric:tabular-nums; color:#555; }
.progress b.ok { color:#2a8f2a; } .progress b.bad { color:#c00; }
.topbar select, .topbar button { font-size:.9rem; padding:.3rem .7rem; border-radius:8px;
          border:1px solid #ccc; background:#fff; cursor:pointer; }
.topbar button.primary { background:#0a67d3; color:#fff; border-color:#0a67d3; }
main { padding: 1rem 2rem 4rem; }
.card { background:#fff; border-radius:10px; padding:1rem 1.2rem; margin-bottom:1rem;
        box-shadow:0 1px 3px rgba(0,0,0,.1); border-left:4px solid transparent; }
.card.warn { border-left-color:#d33; }
.card[data-state="ok"]   { border-left-color:#2a8f2a; background:#f7fcf7; }
.card[data-state="issue"]{ border-left-color:#c00; background:#fff7f7; }
.hd { display:flex; gap:.8rem; align-items:baseline; flex-wrap:wrap; }
.id { font-family:ui-monospace,monospace; color:#666; }
.status { font-size:.75rem; padding:.1rem .5rem; border-radius:1rem; background:#ffe6b3; }
.status.reviewed { background:#c9f0c9; }
.cols { display:grid; grid-template-columns:1fr 1fr; gap:1rem; margin-top:.6rem; }
.cols pre { white-space:pre-wrap; margin:0; font-family:inherit; font-size:.9rem;
            line-height:1.6; background:#fafafa; padding:.6rem; border-radius:6px; }
.problems { color:#c00; font-size:.85rem; margin-top:.4rem; }
.review { display:flex; gap:.6rem; margin-top:.7rem; align-items:flex-start; }
.review button { width:44px; height:36px; font-size:1.1rem; border-radius:8px;
                 border:1px solid #ccc; background:#fff; cursor:pointer; }
.review button.on-ok  { background:#2a8f2a; color:#fff; border-color:#2a8f2a; }
.review button.on-bad { background:#c00; color:#fff; border-color:#c00; }
.review textarea { flex:1; min-height:36px; border-radius:8px; border:1px solid #ccc;
                   padding:.4rem .6rem; font:inherit; font-size:.88rem; resize:vertical; }
.hidden { display:none; }
</style></head><body>
<div class="topbar">
 <h1>__TITLE__ — 翻譯校對（共 __COUNT__ 張__WARNTXT__）</h1>
 <span class="progress" id="progress"></span>
 <select id="filter">
  <option value="all">顯示全部</option>
  <option value="todo">只看未校對</option>
  <option value="issue">只看打✗的</option>
  <option value="ok">只看打✓的</option>
 </select>
 <button id="export" class="primary">匯出校對結果</button>
 <button id="copyIssues">複製✗清單</button>
 <button id="reset">清除進度</button>
</div>
<main>
__ROWS__
</main>
<script>
const KEY = "ws-review-BRD-W139";
const state = JSON.parse(localStorage.getItem(KEY) || "{}");
const cards = Array.from(document.querySelectorAll(".card"));

function save() { localStorage.setItem(KEY, JSON.stringify(state)); }

function render(card) {
  const id = card.dataset.id;
  const st = state[id] || {};
  card.dataset.state = st.status || "";
  card.querySelector(".btn-ok").className  = "btn-ok"  + (st.status === "ok"    ? " on-ok"  : "");
  card.querySelector(".btn-bad").className = "btn-bad" + (st.status === "issue" ? " on-bad" : "");
  const ta = card.querySelector("textarea");
  if (ta.value !== (st.note || "")) ta.value = st.note || "";
}

function renderProgress() {
  let ok = 0, bad = 0;
  for (const card of cards) {
    const st = (state[card.dataset.id] || {}).status;
    if (st === "ok") ok++; else if (st === "issue") bad++;
  }
  document.getElementById("progress").innerHTML =
    `<b class="ok">✓ ${ok}</b>　<b class="bad">✗ ${bad}</b>　未看 ${cards.length - ok - bad}`;
}

function applyFilter() {
  const mode = document.getElementById("filter").value;
  for (const card of cards) {
    const st = (state[card.dataset.id] || {}).status || "";
    const show = mode === "all"
      || (mode === "todo" && !st)
      || (mode === "issue" && st === "issue")
      || (mode === "ok" && st === "ok");
    card.classList.toggle("hidden", !show);
  }
}

for (const card of cards) {
  const id = card.dataset.id;
  card.querySelector(".btn-ok").addEventListener("click", () => {
    const st = state[id] || (state[id] = {});
    st.status = st.status === "ok" ? "" : "ok";
    save(); render(card); renderProgress(); applyFilter();
  });
  card.querySelector(".btn-bad").addEventListener("click", () => {
    const st = state[id] || (state[id] = {});
    st.status = st.status === "issue" ? "" : "issue";
    save(); render(card); renderProgress(); applyFilter();
    if (st.status === "issue") card.querySelector("textarea").focus();
  });
  card.querySelector("textarea").addEventListener("input", (event) => {
    const st = state[id] || (state[id] = {});
    st.note = event.target.value;
    save();
  });
  render(card);
}
renderProgress();
document.getElementById("filter").addEventListener("change", applyFilter);

document.getElementById("export").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify(state, null, 1)], {type: "application/json"});
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "review_result.json";
  a.click();
});

document.getElementById("copyIssues").addEventListener("click", () => {
  const lines = [];
  for (const card of cards) {
    const st = state[card.dataset.id] || {};
    if (st.status === "issue") {
      lines.push(`${card.dataset.id}：${st.note || "（未填備註）"}`);
    }
  }
  navigator.clipboard.writeText(lines.join("\\n") || "（沒有打✗的卡片）");
  alert(`已複製 ${lines.length} 筆到剪貼簿`);
});

document.getElementById("reset").addEventListener("click", () => {
  if (confirm("確定要清除所有勾選與備註嗎？")) {
    localStorage.removeItem(KEY);
    location.reload();
  }
});
</script>
</body></html>"""

ROW = """<div class="card{warn}" data-id="{id}">
 <div class="hd"><b>{name_jp}</b> ⇄ <b>{name_zh}</b>
  <span class="id">{id}</span><span>{meta}</span>
  <span class="status {status}">{status_label}</span></div>
 <div class="cols"><pre>{jp}</pre><pre>{zh}</pre></div>
 {problems}
 <div class="review">
  <button class="btn-ok" title="沒問題">✓</button>
  <button class="btn-bad" title="有問題">✗</button>
  <textarea placeholder="要改什麼？（例：卡名改成◯◯／第2行的「你」應為「對手」）"></textarea>
 </div>
</div>"""


def main():
    ap = argparse.ArgumentParser(
        description="自動驗證卡表譯文，並產出日中對照的人工校對頁")
    ap.add_argument("--cards", required=True,
                    help="要驗證的卡表，例如 sets/uma_cards.json")
    ap.add_argument("--out", default=None,
                    help="校對頁輸出位置（預設為卡表同目錄的 review_<key>.html）")
    args = ap.parse_args()

    data = load_json(args.cards)
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
    # 標題從卡表自己的 meta 取，不要寫死——13 部作品共用這支腳本，
    # 寫死的話拿去校對別部作品，頁面標題會指向錯的系列
    m = data.get("meta", {})
    title = html.escape(f"{m.get('title_code', '?')} {m.get('title_name_zh', '?')}")
    page = (PAGE
            .replace("__TITLE__", title)
            .replace("__COUNT__", str(len(data["cards"])))
            .replace("__WARNTXT__", f"・自動驗證未通過 {failed} 張" if failed else "")
            .replace("__ROWS__", "\n".join(rows)))
    if args.out:
        out = args.out
    else:
        base = os.path.basename(args.cards).replace("_cards.json", "")
        out = os.path.join(os.path.dirname(args.cards) or ".", f"review_{base}.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page)
    print(f"驗證：{len(data['cards'])} 張、未通過 {failed} 張 → {out}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
