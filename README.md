# WS 棕色塵埃2 牌組管理器（WSDeckBuilder）

依《WS牌組管理器_開發計劃書 v1.5》實作。個人使用，不上架。

## 結構

```
WSDeckBuilder/
├── WSDeckBuilder.xcodeproj    iOS App（SwiftUI，iOS 17+）
├── WSDeckBuilder/             App 原始碼 + Resources/brd_cards.json
├── WSDeckBuilderTests/        單元測試（DeckValidator / CardSearch）
└── tools/                     階段一 Python 資料管線（不納入 Xcode target）
    ├── fetch_cards.py         抓取 ws-tcg 官網卡表 → raw_cards.json
    ├── glossary.json          術語對照表（§3.4，台灣圈子慣例）
    ├── translations/          繁中譯文（名稱＋能力文字）
    ├── translate.py           三層翻譯管線 → brd_cards.json
    ├── validate.py            自動化驗證 + 產出 review.html 校對頁
    └── review.html            日中對照人工校對頁
```

## M0 驗證結果（2026-07-26）

- 卡表 API：`GET https://ws-tcg.com/manage/CardListUser/searchJson?keyword=BRD/W139&keyword_type[]=no&show_page_count=120&page=N`
- 卡圖網址：`https://ws-tcg.com/wordpress/wp-content/images/cardlist/` + item `picture` 欄位
- 必須設定瀏覽器 User-Agent（預設 curl UA 會 404）
- BRD/W139 共 304 個刷版、140 張唯一卡片（含 TD 17 張、PR、SP 特典）
- 注意：`-113`~`-122`、`-P02` 為 SP 特典卡，僅存在燙金刷版，無普卡

## 資料更新流程

```bash
cd tools
python3 fetch_cards.py            # 官網 → raw_cards.json
python3 translate.py              # 套用 translations/ → brd_cards.json（含自動驗證）
python3 validate.py               # 重跑驗證 + 產出 review.html
cp brd_cards.json ../WSDeckBuilder/Resources/
```

人工校對後把 `translation_status` 改為 `reviewed`（目前全部為 `machine`）。

## 建置與測試

```bash
xcodebuild -project WSDeckBuilder.xcodeproj -scheme WSDeckBuilder \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## 版權

卡片文字與圖片著作權屬 Bushiroad 及原作品權利方。本專案僅供個人使用，
不散布資料檔與圖片快取；卡圖採線上載入＋本機快取，來源始終是官方網址。
