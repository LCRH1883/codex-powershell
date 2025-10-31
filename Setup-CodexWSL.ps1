## Deprecated: Setup-CodexWSL.ps1
# Delegates to Setup-Codex.ps1 for backward compatibility.
$ErrorActionPreference = 'Stop'
Write-Host 'Setup-CodexWSL.ps1 is deprecated. Running Setup-Codex.ps1...' -ForegroundColor Yellow
$script = Join-Path $PSScriptRoot 'Setup-Codex.ps1'
if (!(Test-Path $script)) { throw "Setup-Codex.ps1 not found in $PSScriptRoot" }
& $script
