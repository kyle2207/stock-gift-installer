# 悠買 buysg 使用手冊

一行安裝的股票下單 CLI —— Windows / macOS / Linux。

## 系統需求

- 以下任一 64 位元系統：**Windows 10 / 11**、**macOS（Apple 晶片 / arm64）**、**Linux（x86_64）**
- 網路連線（安裝器會自動處理其餘所有前置需求，包含 Python）

## 首次設定流程

首次為一次性設定，依序完成步驟 1–3 即可開始使用；此後每次執行僅需 `buysg`。

1. **申請券商程式交易 API 並取得憑證**（步驟 1）：券商審核約需數個工作天，建議優先辦理。
2. **安裝 buysg**（步驟 2）：單行指令，可於等待審核期間完成。
3. **登入、放入憑證並執行 `buysg doctor` 健檢**（步驟 3）：逐項通過即完成設定。

## 步驟 1：申請券商程式交易 API 並取得憑證

buysg 以**你本人的證券帳戶**下單，須具備券商「程式交易 API」憑證。請就你開戶的券商辦理
（玉山、富邦擇一，或兩家皆設）。券商審核約需數個工作天，建議先送出申請，並於等待期間進行步驟 2；
若已啟用該券商之程式交易 API，可略過本步驟。

### 玉山證券（E.SUN）

請依玉山官方 [程式交易 API — 前置準備](https://www.esunsec.com.tw/trading-platforms/api-trading/docs/prerequisites/) 辦理：

1. **申請 API 服務**：於前置準備頁申請憑證、簽署服務同意書後送出，等待審核（約 1–3 個工作天，
   通過後會收到「【玉山證券】交易 API 申請完成通知」）。
2. **完成模擬測試**：審核通過後登入金鑰管理網站，匯出憑證檔（`ID_日期.p12`）、下載模擬環境設定檔，
   並依頁面指示完成模擬下單。
3. **申請正式金鑰**：模擬測試成功後，於「API 正式金鑰」下載正式環境設定檔。
4. **取得憑證**：完成後你會具備**憑證檔（`.p12`）** 與正式環境**設定檔 `config.ini`**，請妥善保存，步驟 3 將使用。

### 富邦證券（Fubon）

請依富邦官方 [新一代 API — 準備工作](https://www.fbs.com.tw/TradeAPI/docs/trading/prepare/) 辦理：

1. **準備富邦證券帳戶**：尚未開戶者，先完成線上開戶。
2. **申請並下載憑證**：至富邦憑證管理入口，下載並執行「富邦證券憑證管理工具（TCEM.exe）」，
   完成登入與 OTP 驗證後取得憑證；憑證預設存於本機 `C:\CAFubon\<身分證字號>`，檔名為 `<身分證字號>.pfx`。
3. **簽署聲明並完成連線測試**：依官方線上 SOP 簽署「API 使用風險暨聲明書」，並執行富邦連線測試工具確認憑證可用。
4. **取得憑證**：完成後你會具備**憑證檔（`<身分證字號>.pfx`）**，請妥善保存，步驟 3 將使用
   （交易 SDK `fubon_neo` 由 buysg 安裝器自動下載，無需自行安裝）。

## 步驟 2：安裝 buysg

### Windows

開啟 **PowerShell**，貼上一行：

```powershell
irm https://raw.githubusercontent.com/kyle2207/buysg-installer/main/install.ps1 | iex
```

### macOS / Linux

開啟**終端機（Terminal）**，貼上一行：

```bash
curl -fsSL https://raw.githubusercontent.com/kyle2207/buysg-installer/main/install.sh | bash
```

安裝器會自動完成（全程不需要 GitHub 帳號、不需要 Git）：

1. 檢查 / 自動安裝 Python 3.12（Windows 用 winget、macOS 用 Homebrew、Linux 用 apt / dnf / pyenv）
2. 從本 repo 的 Releases 下載程式核心
3. 從**券商官方網站**下載交易 SDK（玉山 esun_trade / esun_marketdata、富邦 fubon_neo，非由我們提供或轉發）
4. 建立獨立執行環境與 `buysg` 指令（加入使用者 PATH，不需系統管理員）

> 安裝當下的視窗即可使用 `buysg`；其他已開啟的視窗需重新開啟才能辨識指令。安裝完成後請接續步驟 3。

## 步驟 3：登入、放入憑證與健檢

1. **登入零股悠帳號**：執行 `buysg login`，以 Google / Facebook 登入（與零股悠網站同一帳號，2026 年免費）。

2. **放入步驟 1 取得的憑證**：置於 buysg 憑證資料夾，一個資料夾對應一個帳戶：

   ```
   %LOCALAPPDATA%\buysg\home\certificates\        （macOS / Linux：~/.local/share/buysg/home/certificates/）
   └── <esun 或 fubon>\
       └── <USERNAME>\            ← 一個資料夾對應一個帳戶（buysg 自動掃描）
           ├── config.ini          ← 該券商 SDK 設定檔
           └── 憑證檔（.p12 / .pfx）
   ```

   - **玉山**：建立 `esun\<USERNAME>\`，將玉山提供的 `config.ini` 與 `.p12` 一併放入。
   - **富邦**：建立 `fubon\<USERNAME>\`，僅放入 `.pfx`；執行 `buysg doctor` 會自動生成 `config.ini`
     範本（`CertPath` 已預填），補齊以下三欄後存檔：

     ```ini
     [Account]
     Username     = 你的身分證字號
     Password     = 你的登入密碼
     CertPassword = 你的憑證密碼
     ```

3. **健檢**：執行 `buysg doctor`，逐項通過即完成設定，可開始下單（預設為測試模式，僅列出清單、不會實際下單）。

> 可同時設定玉山與富邦帳戶，下單時於選單勾選欲使用的帳戶。
> 所填帳密與憑證密碼於 `buysg doctor` 通過時將就地加密（Windows DPAPI／macOS · Linux keyring），
> 僅存於本機、不會上傳（詳見「隱私與帳密安全」）。

⚠️ 請以**本人帳戶與憑證**使用 buysg。若有代理他人下單的需求，依證券商規定須先臨櫃辦理
「委託代理買賣授權」；未經合法授權使用他人帳戶，可能涉及法律責任。

## 隱私與帳密安全

券商帳密與憑證**只存在你的電腦**、只用於呼叫券商**官方 SDK** 登入，
驗證後自動加密保護（Windows 用 DPAPI、macOS / Linux 用系統鑰匙圈 keyring），**不會上傳到任何地方**。
完整聲明見 [PRIVACY.md](https://github.com/kyle2207/buysg-installer/blob/main/PRIVACY.md)。

## 程式設定檔（config.ini）

首次執行 `buysg` 時，會在 `%LOCALAPPDATA%\buysg\home\config\config.ini` **自動生成**安全預設，
**一般使用者無需手動編輯**（此為 buysg 程式本身的設定檔，與步驟 3 各券商資料夾內的憑證 `config.ini` 不同）：

- **資料來源**：公開資料，不需要任何帳號密碼。
- **預設測試模式**：每次執行時，互動選單的「實際下單？」預設為「否」——只列出會下單的清單、不會真的下單；
  確認清單無誤後，在選單把該項改為「是」即實際下單。

> 進階：`config.ini` 的 `[TRADING] dry_run` 只是上述選單的**預設值**（`true` = 預設不下單），平時無需更動。

## 指令

| 指令 | 說明 |
|---|---|
| `buysg` | 互動選單下單（分類 / 價值 / 股價上限 / 帳戶勾選；預設模式） |
| `buysg login` | 登入 / 註冊零股悠帳號（Google / Facebook，2026 免費） |
| `buysg preview` | 只看當期「確定有紀念品」清單（免登入券商） |
| `buysg balance` | 只查各帳戶可用交割餘額 + 近日交割款，不下單 |
| `buysg cancel` | 列出可取消的委託，選股票代號後刪單 |
| `buysg accounts` | 設定預設啟用帳戶並寫回設定檔（免手改 config） |
| `buysg doctor` | 環境健檢（設定 / 憑證 / 帳號 / 券商 SDK / 資料來源） |
| `buysg update` | 更新到最新版 |
| `buysg uninstall` | 完整移除（會提醒先備份憑證） |
| `buysg help` | 顯示完整指令說明（等同 `--help`） |

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

> **macOS / Linux** 對應位置：`~/.local/share/buysg/`（`home/` 一樣放你的資料、更新不動；`buysg`
> 指令在 `~/.local/bin/buysg`）。憑證放 `~/.local/share/buysg/home/certificates/<esun|fubon>/<名稱>/`，結構與上方相同。

## 疑難排解

- 任何問題先跑 `buysg doctor`，它會逐項標出缺什麼、該放哪
- 新開的視窗找不到 `buysg` 指令 → 重開一個終端機視窗（Windows：PowerShell；macOS / Linux：Terminal，或先 `source ~/.zshrc`）
- 想砍掉重來：`buysg uninstall` 後重跑安裝一行（憑證記得先備份）

---

<details>
<summary>進階：用 Scoop 安裝（給熟悉套件管理器的使用者）</summary>

若你已用 [Scoop](https://scoop.sh)：

```powershell
scoop bucket add buysg https://github.com/kyle2207/buysg-installer
scoop install buysg
```

之後 `scoop update buysg` / `scoop uninstall buysg`（憑證/設定保留在
`%USERPROFILE%\scoop\persist\buysg\home\`，除非加 `--purge`）。功能與一行安裝相同。
</details>
