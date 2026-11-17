# build_windows_installer.ps1 - Automated Windows Release & Installer Builder
param(
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Building PodQuick Windows Setup Installer" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Flutter Release Build
if (-not $SkipFlutterBuild) {
    Write-Host "`n[1/3] Compiling Flutter Windows Release..." -ForegroundColor Yellow
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build windows failed with code $LASTEXITCODE"
    }
} else {
    Write-Host "`n[1/3] Skipping Flutter build, using existing release files..." -ForegroundColor DarkGray
}

# 2. Locate Inno Setup Compiler
Write-Host "`n[2/3] Locating Inno Setup Compiler (ISCC.exe)..." -ForegroundColor Yellow
$isccPaths = @(
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "C:\Users\67502\AppData\Local\Programs\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
)

$iscc = $null
foreach ($p in $isccPaths) {
    if ($p -and (Test-Path $p)) {
        $iscc = $p
        break
    }
}

if (-not $iscc) {
    throw "ISCC.exe not found! Please ensure Inno Setup is installed."
}

Write-Host "Found Inno Setup at: $iscc" -ForegroundColor Green

# 3. Compile Installer
Write-Host "`n[3/3] Packaging installer using installer.iss..." -ForegroundColor Yellow
& "$iscc" "installer.iss"
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

$setupPath = "build\PodQuick_Setup.exe"
if (Test-Path $setupPath) {
    $sizeMB = [math]::Round((Get-Item $setupPath).Length / 1MB, 2)
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "  Build successful! Installer created:" -ForegroundColor Green
    Write-Host "  -> $setupPath ($sizeMB MB)" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
} else {
    throw "Setup executable not found at $setupPath"
}
