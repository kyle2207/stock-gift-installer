# =============================================================================
# buysg bootstrap installer (Windows) - compiled-lib edition
#
#   irm https://raw.githubusercontent.com/kyle2207/buysg-installer/main/install.ps1 | iex
#
# What it does (no Git, no GitHub account, no manual downloads):
#   1. Ensure Python 3.12 (auto-install via winget if missing)
#   2. Download the compiled core wheel from this repo's latest GitHub Release
#   3. Download broker SDK wheels from the brokers' OFFICIAL sites
#      (E.SUN esun_trade/esun_marketdata 2.2.0, Fubon fubon_neo 2.2.8)
#   4. Create venv, pip install everything (deps come from PyPI)
#   5. Create the buysg command (user PATH); user data lives in
#      %LOCALAPPDATA%\buysg\home (config auto-generated; put certificates there)
#   6. Run "buysg doctor"
#
# Commands: buysg / login / preview / balance / cancel / accounts / doctor / update / uninstall / help
# NOTE: keep this file pure ASCII (works with irm|iex and PS 5.1 without BOM).
# =============================================================================

$ErrorActionPreference = 'Stop'

$Root   = Join-Path $env:LOCALAPPDATA 'buysg'
$Home2  = Join-Path $Root 'home'
$Venv   = Join-Path $Root 'venv'
$Bin    = Join-Path $Root 'bin'
$Wheels = Join-Path $Root 'wheels'
$RepoApi = 'https://api.github.com/repos/kyle2207/buysg-installer'

# Broker SDK official download sources, keyed by wheel platform tag (consumed in
# section 3). This is the Windows installer, so $Platform is fixed to win_amd64;
# the catalog carries the three supported platforms so install.sh mirrors the exact
# same pinned URLs (keep the two in sync). All URLs below verified live (HTTP 200).
# Intel Mac (macosx_10_12) is intentionally excluded to match release_core.yml and
# install.sh (core wheels built: win_amd64 / linux_x86_64 / macosx_arm64 only).
#   E.SUN esun_trade/esun_marketdata 2.2.0 -- vendor ships win / linux / mac-arm / mac-intel
#   Fubon fubon_neo 2.2.8 -- ships all four as .zip (each unpacks to one whl);
#     bumped from 2.0.1 (win-only) so mac/linux are covered; 2.2.8 API verified
#     compatible with the trader code.
$Platform = 'win_amd64'

$EsunBase  = 'https://www.esunsec.com.tw/trading-platforms/api-trading/binary-packages'
$FubonBase = 'https://www.fbs.com.tw/TradeAPI_SDK/fubon_binary'

$SdkCatalog = @{
    'win_amd64' = @(
        @{ Name = 'esun_trade-2.2.0-cp37-abi3-win_amd64.whl';      Url = "$EsunBase/esun_trade-2.2.0-cp37-abi3-win_amd64.whl" },
        @{ Name = 'esun_marketdata-2.2.0-cp37-abi3-win_amd64.whl'; Url = "$EsunBase/esun_marketdata-2.2.0-cp37-abi3-win_amd64.whl" },
        @{ Name = 'fubon_neo-2.2.8-cp37-abi3-win_amd64.zip';       Url = "$FubonBase/fubon_neo-2.2.8-cp37-abi3-win_amd64.zip" }
    )
    'manylinux_2_17_x86_64' = @(
        @{ Name = 'esun_trade-2.2.0-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl';      Url = "$EsunBase/esun_trade-2.2.0-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl" },
        @{ Name = 'esun_marketdata-2.2.0-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl'; Url = "$EsunBase/esun_marketdata-2.2.0-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl" },
        @{ Name = 'fubon_neo-2.2.8-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.zip';       Url = "$FubonBase/fubon_neo-2.2.8-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.zip" }
    )
    'macosx_11_0_arm64' = @(
        @{ Name = 'esun_trade-2.2.0-cp37-abi3-macosx_11_0_arm64.whl';      Url = "$EsunBase/esun_trade-2.2.0-cp37-abi3-macosx_11_0_arm64.whl" },
        @{ Name = 'esun_marketdata-2.2.0-cp37-abi3-macosx_11_0_arm64.whl'; Url = "$EsunBase/esun_marketdata-2.2.0-cp37-abi3-macosx_11_0_arm64.whl" },
        @{ Name = 'fubon_neo-2.2.8-cp37-abi3-macosx_11_0_arm64.zip';       Url = "$FubonBase/fubon_neo-2.2.8-cp37-abi3-macosx_11_0_arm64.zip" }
    )
}

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# --- 0. migrate from the old "stock-gift" install (renamed to buysg) -----------
$OldRoot = Join-Path $env:LOCALAPPDATA 'stock-gift'
if (Test-Path $OldRoot) {
    Step "Old stock-gift install detected - migrating to buysg"
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    foreach ($item in @('home', 'wheels')) {
        $src = Join-Path $OldRoot $item
        $dst = Join-Path $Root $item
        if ((Test-Path $src) -and -not (Test-Path $dst)) {
            Move-Item $src $dst
            Write-Host "    moved $item"
        }
    }
    # very old clone layout: app\config + app\certificates -> home\
    $OldApp = Join-Path $OldRoot 'app'
    if (Test-Path $OldApp) {
        New-Item -ItemType Directory -Force -Path $Home2 | Out-Null
        foreach ($item in @('config', 'certificates')) {
            $src = Join-Path $OldApp $item
            $dst = Join-Path $Home2 $item
            if ((Test-Path $src) -and -not (Test-Path $dst)) { Move-Item $src $dst }
        }
    }
    # drop the old bin from user PATH, remove old root entirely
    $ob = Join-Path $OldRoot 'bin'
    $up = [Environment]::GetEnvironmentVariable('Path', 'User')
    $np = (($up -split ';') | Where-Object { $_ -and $_ -ne $ob }) -join ';'
    if ($np -ne $up) { [Environment]::SetEnvironmentVariable('Path', $np, 'User') }
    Remove-Item -Recurse -Force $OldRoot
    # old core wheels are named stock_gift-*; drop them so only buysg-* remains
    Get-ChildItem (Join-Path $Wheels 'stock_gift-*.whl') -ErrorAction SilentlyContinue | Remove-Item -Force
    Write-Host "    old install removed (user data kept in home\)"
}

Step "Install location: $Root  (user data: home\)"
New-Item -ItemType Directory -Force -Path $Root, $Bin, $Wheels, $Home2 | Out-Null

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
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
$rel = Invoke-RestMethod "$RepoApi/releases/latest" -Headers @{ 'User-Agent' = 'buysg-installer' }
# release now carries per-platform wheels (win/linux/mac) -- must filter by $Platform,
# else Windows would grab the linux/mac wheel and pip would reject it (wrong platform).
$asset = $rel.assets | Where-Object { $_.name -like 'buysg-*.whl' -and $_.name -like "*$Platform*" } | Select-Object -First 1
if (-not $asset) { Fail "no buysg $Platform wheel in latest release ($($rel.tag_name))" }
$CoreWhl = Join-Path $Wheels $asset.name
if (-not (Test-Path $CoreWhl)) {
    Step "Downloading core: $($asset.name) ($([math]::Round($asset.size/1kb)) KB)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $CoreWhl -UseBasicParsing
} else {
    Write-Host "    core cached: $($asset.name)"
}

# --- 3. broker SDKs from official sites ------------------------------------------
Step "Downloading broker SDKs from official sites (cached if present)"
$SdkUrls = $SdkCatalog[$Platform]
if (-not $SdkUrls) { Fail "no broker SDK sources defined for platform '$Platform'" }
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
# prune stale broker wheels from older versions (e.g. fubon 2.0.1 left in cache after a
# bump to 2.2.8) so pip does not install a stale duplicate alongside the current one.
# Each catalog entry's wheel name = its Name with any .zip suffix swapped to .whl.
$ExpectedWhlNames = $SdkUrls | ForEach-Object { $_.Name -replace '\.zip$', '.whl' }
Get-ChildItem (Join-Path $Wheels '*.whl') |
    Where-Object { ($_.Name -like 'esun_*' -or $_.Name -like 'fubon_*') -and
                   ($ExpectedWhlNames -notcontains $_.Name) } |
    ForEach-Object { Write-Host "    removing stale SDK wheel: $($_.Name)"; Remove-Item $_.FullName -Force }

# identify broker wheels explicitly (avoid picking up stale core wheels)
$SdkWhls = Get-ChildItem (Join-Path $Wheels '*.whl') |
    Where-Object { $_.Name -like 'esun_*' -or $_.Name -like 'fubon_*' }
# each catalog entry yields exactly one whl (a .zip unpacks to a single whl)
$ExpectedWhls = @($SdkUrls).Count
if ($SdkWhls.Count -lt $ExpectedWhls) { Fail "expected $ExpectedWhls broker SDK wheels, found $($SdkWhls.Count)" }

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
if (-not (Test-Path (Join-Path $Venv 'Scripts\buysg.exe'))) {
    Fail "buysg entry point was not created - pip install failed, see errors above."
}

# --- 5. command shim + PATH --------------------------------------------------------
Step "Creating the buysg command"
$shim = @'
@echo off
setlocal
set "ROOT=%LOCALAPPDATA%\buysg"
set "BUYSG_HOME=%ROOT%\home"
if /I "%~1"=="update" goto :update
if /I "%~1"=="uninstall" goto :uninstall
pushd "%BUYSG_HOME%"
"%ROOT%\venv\Scripts\buysg.exe" %*
set EC=%ERRORLEVEL%
popd
exit /b %EC%

:update
"%ROOT%\venv\Scripts\buysg.exe" check-update
if errorlevel 1 goto :doupdate
exit /b 0
:doupdate
echo Updating buysg to the latest release...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/kyle2207/buysg-installer/main/install.ps1 | iex"
exit /b %ERRORLEVEL%

:uninstall
echo This removes the whole folder: %ROOT%
echo NOTE: home\config\config.ini and home\certificates\ are deleted too - back them up first!
set /p CONFIRM="Remove? (y/n): "
if /I not "%CONFIRM%"=="y" (
  echo Cancelled.
  exit /b 0
)
powershell -NoProfile -Command "$b=Join-Path $env:LOCALAPPDATA 'buysg\bin'; $p=[Environment]::GetEnvironmentVariable('Path','User'); $n=(($p -split ';') | Where-Object { $_ -and $_ -ne $b }) -join ';'; [Environment]::SetEnvironmentVariable('Path',$n,'User')"
start "" /min cmd /c "timeout /t 2 >nul & rmdir /s /q "%ROOT%""
echo Removed. buysg will be gone in new terminals.
exit /b 0
'@
[IO.File]::WriteAllText((Join-Path $Bin 'buysg.cmd'), $shim,
    (New-Object System.Text.UTF8Encoding($false)))

$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if (($userPath -split ';') -notcontains $Bin) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$Bin", 'User')
    Write-Host "    Added $Bin to user PATH (new terminals pick it up)"
}
$env:Path += ";$Bin"

# --- 6. first-run guidance + doctor -------------------------------------------------
# config.ini is auto-generated on first run (public data mode, no secrets needed).
# The only manual step: put your broker certificates under home\certificates\.
Write-Host ""
if (-not (Test-Path (Join-Path $Home2 'certificates\esun')) -and
    -not (Test-Path (Join-Path $Home2 'certificates\fubon'))) {
    Write-Host "[ONE MORE STEP] Put your broker certificates here:" -ForegroundColor Yellow
    Write-Host "    $Home2\certificates\<esun|fubon>\<name>\"
    Write-Host "    (esun: SDK config.ini + cert file / fubon: just the .pfx --"
    Write-Host "     a config.ini template is auto-generated by 'buysg doctor')"
    Write-Host ""
}
Step "Running health check (buysg doctor)"
& (Join-Path $Bin 'buysg.cmd') doctor

Write-Host ""
Write-Host "Install finished. Commands:" -ForegroundColor Green
Write-Host "    buysg            # interactive order menu"
Write-Host "    buysg login      # sign in / register (Google or Facebook)"
Write-Host "    buysg preview    # view current gift list (no broker login)"
Write-Host "    buysg balance    # account balance + upcoming settlements"
Write-Host "    buysg cancel     # cancel pending orders (pick by stock code)"
Write-Host "    buysg accounts   # set default accounts"
Write-Host "    buysg doctor     # health check"
Write-Host "    buysg version    # show version / check for updates"
Write-Host "    buysg update     # update (only if a newer release exists)"
Write-Host "    buysg uninstall  # remove everything"
Write-Host "    buysg help       # full command list"
Write-Host ""
Write-Host "Privacy: broker credentials stay on THIS machine only, are used solely to"
Write-Host "log in via the brokers' OFFICIAL SDKs, and are never uploaded. Details:"
Write-Host "    https://github.com/kyle2207/buysg-installer/blob/main/PRIVACY.md"
