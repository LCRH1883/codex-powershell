# Setup-Codex.ps1
$ErrorActionPreference = 'Stop'

# 0) Determine default WSL distro (fallback: Ubuntu)
$distro = ''
try {
  $status = wsl --status 2>$null
  if ($status) {
    $m = [regex]::Match($status, 'Default Distribution:\s*(.+)$', 'Multiline')
    if ($m.Success) { $distro = $m.Groups[1].Value.Trim() }
  }
} catch {}
if ([string]::IsNullOrWhiteSpace($distro)) { $distro = 'Ubuntu' }
Write-Host "Using WSL distro: $distro" -ForegroundColor Cyan

# 1) Remove Windows-side Codex shims
try {
  $npmDir = Join-Path $env:USERPROFILE 'AppData\Roaming\npm'
  if (Test-Path $npmDir) {
    Get-ChildItem -Path $npmDir -Filter 'codex*' -File -ErrorAction SilentlyContinue |
      ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
  }
  Get-Command codex -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -like '*AppData\Roaming\npm*' } |
    ForEach-Object { Remove-Item $_.Source -Force -ErrorAction SilentlyContinue }
  Write-Host 'Removed Windows codex shims (if any).' -ForegroundColor DarkGray
} catch {}

# 2) Install Node 22 (NodeSource) + Codex inside WSL (no NVM)
$wslInstall = @'
set -euo pipefail

# Ensure HOME exists even in non-login shells
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
  HOME="$(getent passwd "$(id -un)" | cut -d: -f6)"
  export HOME
fi
mkdir -p "$HOME"

# Base tools
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg

# NodeSource repo for NodeJS 22
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/nodesource.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/trusted.gpg.d/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null || true

# Install Node.js 22 and Codex
sudo apt-get update -y
sudo apt-get install -y nodejs
sudo npm i -g @openai/codex

# Verify
command -v codex || { echo "Codex not found after install" >&2; exit 1; }
codex --version || true
'@

# Normalize to LF and execute as one command in WSL
$cmd = (($wslInstall -split "`r?`n") -join "`n")
$null = wsl -d $distro bash -lc "$cmd"
if ($LASTEXITCODE -ne 0) {
  throw "WSL install failed with exit code $LASTEXITCODE"
}

# 3) Write wrapper into current host profile (clean replace)
$profilePath = $PROFILE.CurrentUserCurrentHost
if (!(Test-Path $profilePath)) {
  New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$begin = '# BEGIN CODEX WSL WRAPPER'
$end   = '# END CODEX WSL WRAPPER'
$wrapper = @'
# BEGIN CODEX WSL WRAPPER
function Convert-ToWslPath([string]$winPath) {
  if ($winPath -match "^[A-Za-z]:\\") {
    $drive = $winPath.Substring(0,1).ToLower()
    $rest  = $winPath.Substring(2).Replace('\','/')
    "/mnt/$drive$rest"
  } else { $winPath }
}
function codex {
  param([Parameter(ValueFromRemainingArguments=$true)] $Args)
  $lin = Convert-ToWslPath $PWD.Path
  # Run Codex in WSL at current folder (PATH from NodeSource install)
  wsl -d "___DISTRO___" --cd "$lin" bash -lc 'codex "$@"' -- @Args
}
# END CODEX WSL WRAPPER
'@
$wrapper = $wrapper.Replace('___DISTRO___', $distro)

# Remove existing block and legacy functions, then append fresh block
$devText = Get-Content $profilePath -Raw
$devText = [regex]::Replace($devText, "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))", '')
$devText = [regex]::Replace($devText, '(?s)function\s+Convert-ToWslPath\s*\([^)]*\)\s*\{.*?\}', '')
$devText = [regex]::Replace($devText, '(?s)function\s+codex\s*\{.*?\}', '')
$devText = ($devText.TrimEnd() + "`r`n`r`n" + $wrapper)
Set-Content -Path $profilePath -Value $devText -Encoding UTF8

# 4) Reload and confirm
. $profilePath
Write-Host "Profile updated: $profilePath" -ForegroundColor Cyan
Write-Host "Run: Get-Command codex; codex --version" -ForegroundColor Cyan
