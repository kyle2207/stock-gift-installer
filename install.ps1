# =============================================================================
# stock-gift bootstrap installer (Windows)
#
#   irm https://raw.githubusercontent.com/kyle2207/stock-gift-installer/main/install.ps1 | iex
#
#   1. 確保 Python(>=3.10) 與 Git（缺則 winget 自動安裝）
#   2. clone 來源 repo 到 %LOCALAPPDATA%\stock-gift\app（已存在則 git pull；需登入一次）
#   3. 建 venv、安裝依賴（含 installers/ 下的 whl）、editable 安裝本體
#   4. 建 stock-gift 指令（使用者 PATH，免系統管理員）
#   5. 跑 stock-gift doctor 健檢
#
# 指令：stock-gift / stock-gift doctor / stock-gift update / stock-gift uninstall
# =============================================================================

$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:LOCALAPPDATA 'stock-gift'
$App  = Join-Path $Root 'app'
$Venv = Join-Path $Root 'venv'
$Bin  = Join-Path $Root 'bin'
$Repo = 'kyle2207/StockTool'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# --- 0. 前置 -----------------------------------------------------------------
Step "安裝位置：$Root"
New-Item -ItemType Directory -Force -Path $Root, $Bin | Out-Null

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
}

# --- 1. Python ---------------------------------------------------------------
Step "檢查 Python（需 >= 3.10）"
$py = $null
foreach ($cand in @('python', 'py')) {
    if (Get-Command $cand -ErrorAction SilentlyContinue) {
        try {
            $v = & $cand -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($v -and ([version]$v -ge [version]'3.10')) { $py = $cand; break }
        } catch {}
    }
}
if (-not $py) {
    Step "未找到 Python >= 3.10，以 winget 安裝 Python 3.12 ..."
    winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
    $py = 'python'
}
Write-Host "    Python: $(& $py --version)"

# --- 2. Git ------------------------------------------------------------------
Step "檢查 Git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Step "未找到 Git，以 winget 安裝 ..."
    winget install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
}
Write-Host "    $(git --version)"

# --- 3. 取得程式碼（私有 repo）-------------------------------------------------
if (Test-Path (Join-Path $App '.git')) {
    Step "已存在安裝，更新程式碼（git pull）"
    git -C $App pull --ff-only
} else {
    Step "Clone 來源 repo（第一次會跳出 GitHub 登入視窗，登入一次即可）"
    $cloned = $false
    # 優先用 gh（若已登入）
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            gh repo clone $Repo $App
            if ($LASTEXITCODE -eq 0) { $cloned = $true }
        }
    }
    # 一般 git clone：Git Credential Manager 會自動開瀏覽器 OAuth
    if (-not $cloned) {
        git clone "https://github.com/$Repo.git" $App
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "Clone 失敗（需要 GitHub 認證），兩個辦法擇一後重跑本腳本：" -ForegroundColor Yellow
            Write-Host "  A) winget install GitHub.cli ; gh auth login   （瀏覽器登入）"
            Write-Host "  B) 到 GitHub 產生 read-only PAT，執行："
            Write-Host "     git clone https://<PAT>@github.com/$Repo.git `"$App`""
            exit 1
        }
    }
}

# --- 4. venv + 依賴 ------------------------------------------------------------
$VenvPy = Join-Path $Venv 'Scripts\python.exe'
if (-not (Test-Path $VenvPy)) {
    Step "建立虛擬環境"
    & $py -m venv $Venv
}
Step "安裝依賴（requirements + whl + 本體）"
& $VenvPy -m pip install --upgrade pip --quiet
& $VenvPy -m pip install -r (Join-Path $App 'requirements.txt') --quiet
Get-ChildItem (Join-Path $App 'installers\*.whl') | ForEach-Object {
    & $VenvPy -m pip install $_.FullName --quiet
}
& $VenvPy -m pip install -e $App --quiet

# --- 5. 指令 shim + PATH -------------------------------------------------------
Step "建立 stock-gift 指令"
$shim = @"
@echo off
chcp 65001 >nul
set "ROOT=%LOCALAPPDATA%\stock-gift"
if /I "%~1"=="update" goto :update
if /I "%~1"=="uninstall" goto :uninstall
pushd "%ROOT%\app"
"%ROOT%\venv\Scripts\stock-gift.exe" %*
set EC=%ERRORLEVEL%
popd
exit /b %EC%

:update
echo ==^> git pull
git -C "%ROOT%\app" pull --ff-only
echo ==^> pip sync
"%ROOT%\venv\Scripts\python.exe" -m pip install -r "%ROOT%\app\requirements.txt" --quiet
"%ROOT%\venv\Scripts\python.exe" -m pip install -e "%ROOT%\app" --quiet
echo 更新完成。
exit /b 0

:uninstall
echo 即將移除 stock-gift（整個 %ROOT% 資料夾）。
echo 注意：app\config\config.ini 與 app\certificates\ 會一併刪除，請先自行備份！
set /p CONFIRM="確定移除? (y/n): "
if /I not "%CONFIRM%"=="y" echo 已取消。&& exit /b 0
powershell -NoProfile -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); $n=(($p -split ';') | Where-Object { $_ -and ($_ -ne ('{0}\bin' -f $env:LOCALAPPDATA + '\stock-gift')) -and ($_ -ne ($env:LOCALAPPDATA + '\stock-gift\bin')) }) -join ';'; [Environment]::SetEnvironmentVariable('Path',$n,'User')"
start "" /min cmd /c "timeout /t 2 >nul & rmdir /s /q "%ROOT%""
echo 已移除（資料夾於背景刪除；新開的終端機不再有 stock-gift 指令）。
exit /b 0
"@
[IO.File]::WriteAllText((Join-Path $Bin 'stock-gift.cmd'), $shim,
    (New-Object System.Text.UTF8Encoding($false)))

$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if (($userPath -split ';') -notcontains $Bin) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$Bin", 'User')
    Write-Host "    已將 $Bin 加入使用者 PATH（新終端機生效）"
}
$env:Path += ";$Bin"

# --- 6. 首次引導 + 健檢 ---------------------------------------------------------
Write-Host ""
if (-not (Test-Path (Join-Path $App 'config\config.ini'))) {
    Write-Host "【還差一步】從舊機器複製這兩樣到安裝目錄：" -ForegroundColor Yellow
    Write-Host "    1. config\config.ini   → $App\config\"
    Write-Host "    2. certificates\ 整包  → $App\certificates\"
    Write-Host ""
}
Step "執行環境健檢（stock-gift doctor）"
& (Join-Path $Bin 'stock-gift.cmd') doctor

Write-Host ""
Write-Host "安裝完成。常用指令：" -ForegroundColor Green
Write-Host "    stock-gift            # 互動選單"
Write-Host "    stock-gift doctor     # 環境健檢"
Write-Host "    stock-gift update     # 更新到最新版"
Write-Host "    stock-gift uninstall  # 完整移除"
