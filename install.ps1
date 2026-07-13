# =============================================================================
# stock-gift bootstrap installer (Windows)
#
#   irm https://raw.githubusercontent.com/kyle2207/stock-gift-installer/main/install.ps1 | iex
#
#   1. Ensure Python (>=3.10) and Git (auto-install via winget if missing)
#   2. Clone source repo to %LOCALAPPDATA%\stock-gift\app (git pull if exists;
#      GitHub sign-in prompted once)
#   3. Create venv, install deps (requirements + installers\*.whl) + editable app
#   4. Create the stock-gift command (user PATH, no admin needed)
#   5. Run "stock-gift doctor" health check
#
# Commands: stock-gift / stock-gift doctor / stock-gift update / stock-gift uninstall
# NOTE: keep this file pure ASCII (works with irm|iex and PS 5.1 without BOM).
# =============================================================================

$ErrorActionPreference = 'Stop'

$Root = Join-Path $env:LOCALAPPDATA 'stock-gift'
$App  = Join-Path $Root 'app'
$Venv = Join-Path $Root 'venv'
$Bin  = Join-Path $Root 'bin'
$Repo = 'kyle2207/StockTool'

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# --- 0. dirs -----------------------------------------------------------------
Step "Install location: $Root"
New-Item -ItemType Directory -Force -Path $Root, $Bin | Out-Null

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path','User')
}

# --- 1. Python ---------------------------------------------------------------
Step "Checking Python (>= 3.10)"
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
    Step "Python >= 3.10 not found, installing via winget..."
    winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
    $py = 'python'
}
Write-Host "    Python: $(& $py --version)"

# --- 2. Git ------------------------------------------------------------------
Step "Checking Git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Step "Git not found, installing via winget..."
    winget install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    Refresh-Path
}
Write-Host "    $(git --version)"

# --- 3. clone / update source ------------------------------------------------
if (Test-Path (Join-Path $App '.git')) {
    Step "Existing install found, updating (git pull)"
    git -C $App pull --ff-only
} else {
    Step "Cloning source repo (a GitHub sign-in window may pop up once)"
    $cloned = $false
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            gh repo clone $Repo $App
            if ($LASTEXITCODE -eq 0) { $cloned = $true }
        }
    }
    if (-not $cloned) {
        git clone "https://github.com/$Repo.git" $App
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "Clone failed (GitHub auth needed). Pick one, then re-run this script:" -ForegroundColor Yellow
            Write-Host "  A) winget install GitHub.cli ; gh auth login"
            Write-Host "  B) create a read-only PAT on GitHub, then:"
            Write-Host "     git clone https://<PAT>@github.com/$Repo.git `"$App`""
            exit 1
        }
    }
}
if (-not (Test-Path (Join-Path $App 'pyproject.toml'))) {
    Fail "pyproject.toml not found in repo - the source repo is not up to date yet."
}

# --- 4. venv + deps ------------------------------------------------------------
$VenvPy = Join-Path $Venv 'Scripts\python.exe'
if (-not (Test-Path $VenvPy)) {
    Step "Creating virtualenv"
    & $py -m venv $Venv
}
Step "Installing dependencies (requirements + wheels + app)"
& $VenvPy -m pip install --upgrade pip --quiet
& $VenvPy -m pip install -r (Join-Path $App 'requirements.txt') --quiet
Get-ChildItem (Join-Path $App 'installers\*.whl') | ForEach-Object {
    & $VenvPy -m pip install $_.FullName --quiet
}
& $VenvPy -m pip install -e $App --quiet
if (-not (Test-Path (Join-Path $Venv 'Scripts\stock-gift.exe'))) {
    Fail "stock-gift entry point was not created - pip install -e failed, see errors above."
}

# --- 5. command shim + PATH ----------------------------------------------------
Step "Creating the stock-gift command"
$shim = @'
@echo off
setlocal
set "ROOT=%LOCALAPPDATA%\stock-gift"
if /I "%~1"=="update" goto :update
if /I "%~1"=="uninstall" goto :uninstall
pushd "%ROOT%\app"
"%ROOT%\venv\Scripts\stock-gift.exe" %*
set EC=%ERRORLEVEL%
popd
exit /b %EC%

:update
echo === git pull ===
git -C "%ROOT%\app" pull --ff-only
echo === pip sync ===
"%ROOT%\venv\Scripts\python.exe" -m pip install -r "%ROOT%\app\requirements.txt" --quiet
"%ROOT%\venv\Scripts\python.exe" -m pip install -e "%ROOT%\app" --quiet
echo Update done.
exit /b 0

:uninstall
echo This removes the whole folder: %ROOT%
echo NOTE: app\config\config.ini and app\certificates\ are deleted too - back them up first!
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

# --- 6. first-run guidance + doctor --------------------------------------------
Write-Host ""
if (-not (Test-Path (Join-Path $App 'config\config.ini'))) {
    Write-Host "[ONE MORE STEP] Copy these two from your old machine:" -ForegroundColor Yellow
    Write-Host "    1. config\config.ini   -> $App\config\"
    Write-Host "    2. certificates\ (all) -> $App\certificates\"
    Write-Host ""
}
Step "Running health check (stock-gift doctor)"
& (Join-Path $Bin 'stock-gift.cmd') doctor

Write-Host ""
Write-Host "Install finished. Commands:" -ForegroundColor Green
Write-Host "    stock-gift            # interactive menu"
Write-Host "    stock-gift doctor     # health check"
Write-Host "    stock-gift update     # update to latest"
Write-Host "    stock-gift uninstall  # remove everything"
