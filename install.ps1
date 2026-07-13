# =============================================================================
# stock-gift bootstrap installer (Windows) - compiled-lib edition
#
#   irm https://raw.githubusercontent.com/kyle2207/stock-gift-installer/main/install.ps1 | iex
#
# What it does (no Git, no GitHub account, no manual downloads):
#   1. Ensure Python 3.12 (auto-install via winget if missing)
#   2. Download the compiled core wheel from this repo's latest GitHub Release
#   3. Download broker SDK wheels from the brokers' OFFICIAL sites
#      (E.SUN esun_trade/esun_marketdata 2.2.0, Fubon fubon_neo 2.0.1)
#   4. Create venv, pip install everything (deps come from PyPI)
#   5. Create the stock-gift command (user PATH); user data lives in
#      %LOCALAPPDATA%\stock-gift\home (config auto-generated; put certificates there)
#   6. Run "stock-gift doctor"
#
# Commands: stock-gift / stock-gift doctor / stock-gift update / stock-gift uninstall
# NOTE: keep this file pure ASCII (works with irm|iex and PS 5.1 without BOM).
# =============================================================================

$ErrorActionPreference = 'Stop'

$Root   = Join-Path $env:LOCALAPPDATA 'stock-gift'
$Home2  = Join-Path $Root 'home'
$Venv   = Join-Path $Root 'venv'
$Bin    = Join-Path $Root 'bin'
$Wheels = Join-Path $Root 'wheels'
$RepoApi = 'https://api.github.com/repos/kyle2207/stock-gift-installer'

# Broker SDK official download sources (exact known-good versions)
$SdkUrls = @(
    @{ Name = 'esun_trade-2.2.0-cp37-abi3-win_amd64.whl';
       Url  = 'https://www.esunsec.com.tw/trading-platforms/api-trading/binary-packages/esun_trade-2.2.0-cp37-abi3-win_amd64.whl' },
    @{ Name = 'esun_marketdata-2.2.0-cp37-abi3-win_amd64.whl';
       Url  = 'https://www.esunsec.com.tw/trading-platforms/api-trading/binary-packages/esun_marketdata-2.2.0-cp37-abi3-win_amd64.whl' },
    @{ Name = 'fubon_neo-2.0.1-cp37-abi3-win_amd64.zip';  # zip contains the whl
       Url  = 'https://www.fbs.com.tw/TradeAPI_SDK/fubon_binary/fubon_neo-2.0.1-cp37-abi3-win_amd64.zip' }
)

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

Step "Install location: $Root  (user data: home\)"
New-Item -ItemType Directory -Force -Path $Root, $Bin, $Wheels, $Home2 | Out-Null

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
}

# --- 0. migrate from old clone-based layout ------------------------------------
$OldApp = Join-Path $Root 'app'
if (Test-Path $OldApp) {
    Step "Old layout detected - migrating config/certificates to home\"
    foreach ($item in @('config','certificates')) {
        $src = Join-Path $OldApp $item
        $dst = Join-Path $Home2 $item
        if ((Test-Path $src) -and -not (Test-Path $dst)) {
            Move-Item $src $dst
            Write-Host "    moved $item -> home\$item"
        }
    }
    Remove-Item -Recurse -Force $OldApp
    if (Test-Path $Venv) { Remove-Item -Recurse -Force $Venv }  # old editable venv is stale
    Write-Host "    old app/venv removed (clean rebuild)"
}

# --- 1. Python 3.12 (wheel is cp312) --------------------------------------------
Step "Checking Python 3.12 (required: compiled core targets cp312)"
$py = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    try { & py -3.12 -c "pass" 2>$null; if ($LASTEXITCODE -eq 0) { $py = 'py -3.12' } } catch {}
}
if (-not $py -and (Get-Command python -ErrorAction SilentlyContinue)) {
    try {
        $v = & python -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
        if ($v -eq '3.12') { $py = 'python' }
    } catch {}
}
if (-not $py) {
    Step "Python 3.12 not found, installing via winget..."
    winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
    $py = 'py -3.12'
}
Write-Host "    Python: $(Invoke-Expression "$py --version")"

# --- 2. core wheel from latest GitHub Release -----------------------------------
Step "Fetching latest release info"
$rel = Invoke-RestMethod "$RepoApi/releases/latest" -Headers @{ 'User-Agent' = 'stock-gift-installer' }
$asset = $rel.assets | Where-Object { $_.name -like 'stock_gift-*.whl' } | Select-Object -First 1
if (-not $asset) { Fail "no stock_gift wheel asset in latest release ($($rel.tag_name))" }
$CoreWhl = Join-Path $Wheels $asset.name
if (-not (Test-Path $CoreWhl)) {
    Step "Downloading core: $($asset.name) ($([math]::Round($asset.size/1kb)) KB)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $CoreWhl -UseBasicParsing
} else {
    Write-Host "    core cached: $($asset.name)"
}

# --- 3. broker SDKs from official sites ------------------------------------------
Step "Downloading broker SDKs from official sites (cached if present)"
foreach ($sdk in $SdkUrls) {
    $dst = Join-Path $Wheels $sdk.Name
    if (-not (Test-Path $dst)) {
        Write-Host "    downloading $($sdk.Name) ..."
        Invoke-WebRequest $sdk.Url -OutFile $dst -UseBasicParsing
    } else {
        Write-Host "    cached: $($sdk.Name)"
    }
    if ($sdk.Name -like '*.zip') {
        Expand-Archive -Path $dst -DestinationPath $Wheels -Force
    }
}
$SdkWhls = Get-ChildItem (Join-Path $Wheels '*.whl') | Where-Object { $_.Name -notlike 'stock_gift-*' }
if ($SdkWhls.Count -lt 3) { Fail "expected 3 broker SDK wheels, found $($SdkWhls.Count)" }

# --- 4. venv + install ------------------------------------------------------------
$VenvPy = Join-Path $Venv 'Scripts\python.exe'
if (-not (Test-Path $VenvPy)) {
    Step "Creating virtualenv (Python 3.12)"
    Invoke-Expression "$py -m venv `"$Venv`""
}
Step "Installing core + broker SDKs (deps auto-resolved from PyPI)"
& $VenvPy -m pip install --upgrade pip --quiet
foreach ($w in $SdkWhls) { & $VenvPy -m pip install $w.FullName --quiet }
& $VenvPy -m pip install $CoreWhl --force-reinstall --upgrade --quiet
if (-not (Test-Path (Join-Path $Venv 'Scripts\stock-gift.exe'))) {
    Fail "stock-gift entry point was not created - pip install failed, see errors above."
}

# --- 5. command shim + PATH --------------------------------------------------------
Step "Creating the stock-gift command"
$shim = @'
@echo off
setlocal
set "ROOT=%LOCALAPPDATA%\stock-gift"
set "STOCK_GIFT_HOME=%ROOT%\home"
if /I "%~1"=="update" goto :update
if /I "%~1"=="uninstall" goto :uninstall
pushd "%STOCK_GIFT_HOME%"
"%ROOT%\venv\Scripts\stock-gift.exe" %*
set EC=%ERRORLEVEL%
popd
exit /b %EC%

:update
echo Re-running installer to fetch the latest release...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/kyle2207/stock-gift-installer/main/install.ps1 | iex"
exit /b %ERRORLEVEL%

:uninstall
echo This removes the whole folder: %ROOT%
echo NOTE: home\config\config.ini and home\certificates\ are deleted too - back them up first!
set /p CONFIRM="Remove? (y/n): "
if /I not "%CONFIRM%"=="y" (
  echo Cancelled.
  exit /b 0
)
powershell -NoProfile -Command "$b=Join-Path $env:LOCALAPPDATA 'stock-gift\bin'; $p=[Environment]::GetEnvironmentVariable('Path','User'); $n=(($p -split ';') | Where-Object { $_ -and $_ -ne $b }) -join ';'; [Environment]::SetEnvironmentVariable('Path',$n,'User')"
start "" /min cmd /c "timeout /t 2 >nul & rmdir /s /q "%ROOT%""
echo Removed. stock-gift will be gone in new terminals.
exit /b 0
'@
[IO.File]::WriteAllText((Join-Path $Bin 'stock-gift.cmd'), $shim,
    (New-Object System.Text.UTF8Encoding($false)))

$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if (($userPath -split ';') -notcontains $Bin) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$Bin", 'User')
    Write-Host "    Added $Bin to user PATH (new terminals pick it up)"
}
$env:Path += ";$Bin"

# --- 6. first-run guidance + doctor -------------------------------------------------
Write-Host ""
if (-not (Test-Path (Join-Path $Home2 'certificates\esun')) -and
    -not (Test-Path (Join-Path $Home2 'certificates\fubon'))) {
    Write-Host "[ONE MORE STEP] Put your broker certificates here:" -ForegroundColor Yellow
    Write-Host "    $Home2\certificates\<esun|fubon>\<name>\  (SDK config.ini + cert files)"
    Write-Host ""
}
Step "Running health check (stock-gift doctor)"
& (Join-Path $Bin 'stock-gift.cmd') doctor

Write-Host ""
Write-Host "Install finished. Commands:" -ForegroundColor Green
Write-Host "    stock-gift            # interactive menu"
Write-Host "    stock-gift doctor     # health check"
Write-Host "    stock-gift update     # update to latest release"
Write-Host "    stock-gift uninstall  # remove everything"
