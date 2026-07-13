# buysg

Windows 一行安裝的股票下單 CLI。

## 系統需求

- Windows 10 / 11（64 位元）
- 網路連線（安裝器會自動處理其餘所有前置需求，包含 Python）

## 安裝

開啟 **PowerShell**，貼上一行：

```powershell
irm https://raw.githubusercontent.com/kyle2207/buysg-installer/main/install.ps1 | iex
```

安裝器會自動完成（全程不需要 GitHub 帳號、不需要 Git）：

1. 檢查 / 自動安裝 Python 3.12
2. 從本 repo 的 Releases 下載程式核心
3. 從**券商官方網站**下載交易 SDK（玉山 esun_trade / esun_marketdata、富邦 fubon_neo）
4. 建立獨立執行環境與 `buysg` 指令（加入使用者 PATH，不需系統管理員）
5. 執行 `buysg doctor` 環境健檢

> 安裝當下的視窗可直接使用 `buysg`；其他已開啟的視窗需重開才會認得指令。

## 安裝後的唯一手動步驟：放入你的券商憑證

把你自己的券商憑證資料夾放到：

```
%LOCALAPPDATA%\buysg\home\certificates\
└── <esun 或 fubon>\
    └── <自訂名稱>\            ← 一個資料夾 = 一個帳戶（會自動掃描）
        ├── config.ini          ← 該券商 SDK 的設定檔
        └── 憑證檔（.p12 / .pfx）
```

範例（玉山一個帳戶 + 富邦一個帳戶）：

```
%LOCALAPPDATA%\buysg\home\certificates\
├── esun\
│   └── kyle\
│       ├── config.ini
│       └── xxxxxxxx.p12
└── fubon\
    └── kyle\
        ├── config.ini
        └── xxxxxxxx.pfx
```

- 憑證與 SDK 設定檔請向你的券商申請（玉山程式交易 API / 富邦新一代 API）
- 放好後執行 `buysg doctor`，會逐項告訴你還缺什麼
- 帳戶資料夾會**自動掃描**，執行時在選單勾選要用哪些帳戶

## 設定檔（config.ini）

第一次執行 `buysg` 會在 `%LOCALAPPDATA%\buysg\home\config\config.ini`
**自動生成**安全預設：

- 資料來源：公開資料（不需要任何帳號密碼）
- `dry_run = true`：**預設測試模式**，只列出會下單的清單、不會真的下單

確認清單沒問題後，把 `dry_run` 改成 `false` 才會實際下單。

## 指令

| 指令 | 說明 |
|---|---|
| `buysg` | 互動選單（分類 / 價值 / 股價上限 / 帳戶勾選） |
| `buysg doctor` | 環境健檢（設定 / 憑證 / SDK / 資料連線） |
| `buysg update` | 更新到最新版 |
| `buysg uninstall` | 完整移除（會提醒先備份憑證） |

## 資料夾結構

```
%LOCALAPPDATA%\buysg\
├── home\           ← 你的資料（設定、憑證、產出的報表）— 更新不會動到
│   ├── config\config.ini
│   ├── certificates\...
│   └── data\order_report.xlsx
├── venv\           ← 程式執行環境（更新時重建）
├── wheels\         ← 下載快取
└── bin\buysg.cmd
```

## 疑難排解

- 任何問題先跑 `buysg doctor`，它會逐項標出缺什麼、該放哪
- 新開的視窗找不到 `buysg` 指令 → 重開一個 PowerShell 視窗
- 想砍掉重來：`buysg uninstall` 後重跑安裝一行（憑證記得先備份）
