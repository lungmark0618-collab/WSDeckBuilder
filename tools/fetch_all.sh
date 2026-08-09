#!/bin/bash
# 多作品批次抓取＋產出（新系列先收錄日文，翻譯後補）
set -e
cd "$(dirname "$0")"
fetch() { # key sets title_jp title_zh
  python3 fetch_cards.py --sets "$2" --title-jp "$3" --title-zh "$4" --out "sets/$1_raw.json"
  python3 translate.py --raw "sets/$1_raw.json" --out "sets/$1_cards.json" 2>/dev/null || true
  echo "== $1 done =="
}
fetch sfn  "SFN/"              "葬送のフリーレン"          "葬送的芙莉蓮"
fetch ovl  "OVL/"              "オーバーロード"            "OVERLORD"
fetch btr  "BTR/"              "ぼっち・ざ・ろっく！"      "孤獨搖滾！"
fetch nik  "NIK/"              "勝利の女神：NIKKE"         "勝利女神：妮姬"
fetch csm  "CSM/"              "チェンソーマン"            "鏈鋸人"
fetch hol  "HOL/"              "ホロライブプロダクション"  "hololive"
fetch uma  "UMA/"              "ウマ娘 プリティーダービー" "賽馬娘"
fetch mygo "BD/W125,BD/WE42"   "BanG Dream! It's MyGO!!!!!" "MyGO!!!!!"
fetch bdgbp "BD/W54,BD/W63,BD/W73,BD/W95,BD/WE34" \
      "BanG Dream! ガールズバンドパーティ！" "BanG Dream! 少女樂團派對"

# ── 2026 環境常見作品（先收日文，譯文之後補）───────────────────
# 挑選依據：日版 Neo-Standard 2026 上半環境的第一線作品（學園偶像大師），
# 加上英日兩邊排行都常出現的幾部。譯文還沒做，translate.py 會原樣保留日文，
# 不會輸出半調子的混雜文。
fetch gim  "GIM/"  "学園アイドルマスター"  "學園偶像大師"
fetch osk  "OSK/"  "【推しの子】"          "【我推的孩子】"
fetch pjs  "PJS/"  "プロジェクトセカイ カラフルステージ！ feat.初音ミク" "世界計畫 繽紛舞台！"
fetch azl  "AZL/"  "アズールレーン"        "碧藍航線"
fetch lrc  "LRC/"  "リコリス・リコイル"    "莉可麗絲"
echo "ALL_DONE"
