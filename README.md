# WS 牌組管理器（WSDeckBuilder）

Weiß Schwarz 的 iOS 牌組管理 App，附一套把官方日文卡表翻成繁體中文的資料管線。
個人自用工具，不上架。

> **非官方粉絲專案**，與 Bushiroad 及各原作品權利方無任何關聯，非商業用途。

打牌時最麻煩的是卡面全日文，看一張要查半天。這個專案做兩件事：**把卡面翻成中文**，
以及**在手機上組牌、驗規則、跟朋友交換牌組**。

## 功能

| | |
|---|---|
| **中文卡面** | 卡名與能力文字全繁體中文，完全離線。右上角一鍵切回日文對照 |
| **依作品瀏覽** | 先選作品再看卡；搜尋列固定在最上面，想直接找卡就打字，不必先選作品 |
| **牌組管理** | 建立多個牌組，可指定同一張卡各稀有度分別放幾張（對照實體收藏用） |
| **規則驗證** | 即時檢查 50 張／CX 8 張／同名 4 張，違規即標紅 |
| **統計** | 等級曲線、顏色分布、判定標誌分布 |
| **牌組出圖** | 把牌組畫成一張圖分享，圖上的 QR 可以直接掃回整副牌組 |
| **卡圖快取** | 首次瀏覽時下載，之後永久保留；要不要用行動數據由你決定 |
| **卡表線上更新** | 出新彈或修正譯文時 App 內更新資料，不必重裝 |

## 卡片資料

**這個 repo 不含任何卡片資料。**

日文卡名與能力文字的著作權屬 Bushiroad 及各原作品權利方，中文譯文是它的衍生著作，
兩者都不該由我散布。所以這裡只有**產生資料的工具**，沒有資料本身
（`.gitignore` 已排除 `WSDeckBuilder/Resources/*_cards.json`）。

要自己建一份：

```bash
cd tools

# 1. 從官方卡表抓取（各作品的 --sets 參數見 fetch_all.sh）
python3 fetch_cards.py --sets "SFN/" \
    --title-jp "葬送のフリーレン" --title-zh "葬送的芙莉蓮" \
    --out sets/sfn_raw.json

# 2. 跑翻譯管線
python3 translate.py --raw sets/sfn_raw.json --out sets/sfn_cards.json

# 3. 放進 App 資源目錄
cp sets/sfn_cards.json ../WSDeckBuilder/Resources/
```

`fetch_all.sh` 是一次跑完全部作品的批次腳本，各作品實際用的 `--sets` 參數都記在裡面，
照抄改一行即可。抓取維持每次請求間隔 1~2 秒，不對官方伺服器造成負擔。

想人工校對譯文，`validate.py` 會產出日中對照頁：

```bash
python3 validate.py --cards sets/sfn_cards.json   # → sets/review_sfn.html
```

> 沒有卡表時 App 會顯示「找不到卡片資料檔」——這是預期行為，先跑完上面的管線。

**只是想把 App 跑起來、不想等爬蟲**，可以直接抓 App 平常在用的那份線上卡表：

```bash
python3 tools/fetch_published_cards.py
```

抓下來的每一份都會驗證（解得開、作品代號對得上、非空）。CI 跑測試前也是走這條路——
23 個測試裡有 9 個需要真實卡表。

## 翻譯管線

WS 的卡面文字高度模板化，這是整件事可行的原因。分三層處理：

1. **術語表確定性取代** — `glossary.json` 把遊戲術語一次換掉（控え室→休息室、
   山札→牌組、パワー→攻擊力…），依台灣圈子慣例校準。這層不經 LLM，結果穩定可預期
2. **規則翻譯** — `machine_translate.py` 用數百條規則處理剩下的連接句構
3. **自動驗證** — 數字集合、`【】` 標記、`《》` 特徵數量必須與原文完全一致，
   譯文不得殘留假名。不通過就退回日文，而不是輸出錯的東西

`《》` 特徵刻意保留日文——對牌時要跟卡面長得一樣才好認。

**卡名不走這條路**。1,753 個描述性前綴裡有 1,560 個（89%）只出現一次；能力文字能靠
規則組合，卡名不行，只能一張一張處理。`translate_helper.py` 就是為了讓這件事可以分批
進行——dump 出未翻的、翻好、apply 回去，中途可以停。

## 建置

需要 Xcode 16+、iOS 17+。

```bash
xcodebuild -scheme WSDeckBuilder -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath <某個路徑>
```

Clone 之後要改兩個地方：`WSDeckBuilder.xcodeproj/project.pbxproj` 裡的
`DEVELOPMENT_TEAM` 與 `PRODUCT_BUNDLE_IDENTIFIER`，換成你自己的。

> ⚠️ `derivedDataPath` 不要放在 iCloud 同步的目錄（桌面、文件夾）底下。
> iCloud 會加上 `com.apple.FinderInfo` 屬性，codesign 會失敗。

跑測試：

```bash
xcodebuild -scheme WSDeckBuilder \
    -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## 結構

```
WSDeckBuilder/
├── App/                 進入點、TabView
├── Models/              Card / CardDatabase / Deck / SearchQuery / DeckValidator
├── Views/
│   ├── Browser/         圖鑑：作品選單 → 卡片網格、搜尋、篩選
│   ├── Deck/            牌組列表、編輯、統計
│   └── Shared/          卡圖、卡片詳情
├── Services/            卡圖快取、網路政策、牌組出圖／掃圖、卡表線上更新
└── Resources/           卡表 JSON（不進版控，見「卡片資料」）

tools/                   資料管線（不納入 Xcode target）
├── fetch_cards.py       抓取官方卡表
├── glossary.json        術語對照表
├── machine_translate.py 規則翻譯
├── translate.py         三層管線 + 驗證
├── translate_helper.py  分批校對用
├── validate.py          重跑驗證並產出日中對照的校對頁
├── check_cards.py       卡表結構健檢
├── make_manifest.py     產生線上更新用的 manifest
├── fetch_published_cards.py  抓已發佈的卡表（免重爬官網）
├── pick_simulator.py    挑一台可用的 iPhone 模擬器（CI 用）
└── backup_translations.sh  備份譯文（不進版控，見「卡片資料」）

docs/開發計劃書.md        設計文件
```

## 設計文件

[`docs/開發計劃書.md`](docs/開發計劃書.md) 記錄了實作過程中的決策與理由——為什麼卡名
不能自動翻、線上更新的版本號為什麼要按作品拆、CX 卡在匯出圖裡為什麼要轉 90°、
`PhotosPicker` 放在 `Menu` 裡為什麼不會彈出、少宣告 `NSPhotoLibraryAddUsageDescription`
會讓分享面板的「儲存影像」整個消失之類的。

比起程式碼本身，那份文件大概更有參考價值。

## 授權

程式碼與文件採 [PolyForm Noncommercial License 1.0.0](LICENSE.md)：可自由使用與修改，
**但不得用於商業用途**。

授權範圍**僅限本 repo 內我自己撰寫的內容**（Swift 程式碼、Python 工具、文件）。
卡片資料不在此 repo 內，也不在授權範圍內——那是權利方的著作，我無權授權。

## 著作權

- 卡片文字與圖片的著作權屬 **Bushiroad** 及各原作品權利方
- 本專案為個人自用工具，非官方、非商業，與權利方無關聯
- **卡圖不隨程式打包也不散布**，一律由 App 從官方網址載入後快取於裝置本機
- 抓取維持低頻率，不對官方伺服器造成負擔

若權利方認為有不妥之處，請開 issue 或來信，我會立即處理。
