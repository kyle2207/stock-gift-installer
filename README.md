# stock-gift installer

股東會紀念品自動下單 CLI（stock-gift）的一行安裝入口。程式碼在私有 repo（[StockTool](https://github.com/kyle2207/StockTool)），本 repo 只放安裝腳本。

## 安裝（Windows，PowerShell）

```powershell
irm https://raw.githubusercontent.com/kyle2207/stock-gift-installer/main/install.ps1 | iex
```

- 自動安裝 Python / Git（缺的話走 winget）
- clone 私有 repo 時會跳 GitHub 登入（一次性）
- 裝完後從舊機器複製 `config\config.ini` 與 `certificates\` 到 `%LOCALAPPDATA%\stock-gift\app\` 下
- `stock-gift doctor` 會逐項告訴你還缺什麼

## 指令

| 指令 | 說明 |
|---|---|
| `stock-gift` | 互動選單下單 |
| `stock-gift doctor` | 環境健檢 |
| `stock-gift update` | 更新到最新版 |
| `stock-gift uninstall` | 完整移除（記得先備份憑證） |
