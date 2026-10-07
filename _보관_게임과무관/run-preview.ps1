$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$logFile = Join-Path $root "run-preview.log"
"[{0}] run-preview start" -f (Get-Date) | Set-Content -Encoding UTF8 $logFile

function Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date), $msg
  $line | Add-Content -Encoding UTF8 $logFile
}

try { Log "node: $(node -v)" } catch { Write-Host "[ERROR] node not found"; Read-Host "Press Enter"; exit 1 }
try { Log "npm: $(npm -v)" } catch { Write-Host "[ERROR] npm not found"; Read-Host "Press Enter"; exit 1 }

if (-not (Test-Path (Join-Path $root "node_modules"))) {
  Write-Host "Installing dependencies (first run)..."
  Log "npm install start"
  & npm install *>> $logFile
  Log "npm install done"
}

Write-Host "Building..."
Log "npm run build start"
& npm run build *>> $logFile
if ($LASTEXITCODE -ne 0) {
  Log "build failed: $LASTEXITCODE"
  Write-Host "[ERROR] build failed. See run-preview.log"
  Read-Host "Press Enter to close"
  exit $LASTEXITCODE
}

Start-Process "http://localhost:4173"
Write-Host "Starting preview server..."
Log "npm run preview start"
& npm run preview *>> $logFile
Log "npm run preview exit code: $LASTEXITCODE"
exit $LASTEXITCODE

