$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$logFile = Join-Path $root "run-dev.log"
"[{0}] run-dev start" -f (Get-Date) | Set-Content -Encoding UTF8 $logFile

function Log([string]$msg) {
  $line = "[{0}] {1}" -f (Get-Date), $msg
  $line | Add-Content -Encoding UTF8 $logFile
}

try {
  Log "node: $(node -v)"
} catch {
  Write-Host ""
  Write-Host "[ERROR] node not found in PATH."
  Write-Host "Install Node.js (LTS), then close and reopen terminals."
  Write-Host ""
  Log "node not found: $($_.Exception.Message)"
  Read-Host "Press Enter to close"
  exit 1
}

try {
  Log "npm: $(npm -v)"
} catch {
  Write-Host ""
  Write-Host "[ERROR] npm not found in PATH."
  Write-Host "Reinstall Node.js (npm included) or fix PATH."
  Write-Host ""
  Log "npm not found: $($_.Exception.Message)"
  Read-Host "Press Enter to close"
  exit 1
}

if (-not (Test-Path (Join-Path $root "node_modules"))) {
  Write-Host "Installing dependencies (first run)..."
  Log "npm install start"
  & npm install *>> $logFile
  Log "npm install done"
}

Start-Process "http://localhost:5173"

Write-Host "Starting dev server..."
Log "npm run dev start"
& npm run dev *>> $logFile
Log "npm run dev exit code: $LASTEXITCODE"
exit $LASTEXITCODE

