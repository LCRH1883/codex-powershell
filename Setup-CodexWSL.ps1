# Setup-CodexWSL.ps1

# 0) Preconditions
$ErrorActionPreference = "Stop"
wsl --status | Out-Null

# 1) Remove any Windows-side shims
$winShim = Join-Path $env:USERPROFILE "AppData\Roaming\npm\codex"
if (Test-Path $winShim) { Remove-Item $winShim -Force -ErrorAction SilentlyContinue }
Get-Command codex -ErrorAction SilentlyContinue | Where-Object { $_.Source -like "*AppData\Roaming\npm*" } | ForEach-Object {
  Remove-Item $_.Source -Force -ErrorAction SilentlyContinue
}

# 2) Install Node 22 + Codex inside default WSL (Ubuntu assumed)
$wslInstall = @'
set -e
# Ensure basic tools
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates git

# Install NVM if missing
if [ ! -d "$HOME/.nvm" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi

# Load nvm in this shell
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Ensure non-interactive shells get nvm
if ! grep -q 'NVM_DIR=' "$HOME/.bashrc" 2>/dev/null; then
  {
    echo 'export NVM_DIR="$HOME/.nvm"'
    echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
  } >> "$HOME/.bashrc"
fi

# Node 22 and Codex
nvm install 22
nvm alias default 22
nvm use 22
npm i -g @openai/codex

which codex
codex --version || true
'@

wsl bash -lc "$([string]::Join([environment]::NewLine,($wslInstall -split \"`r?`n\")))"

# 3) Ensure PowerShell profile exists
if (!(Test-Path $PROFILE)) {
  New-Item -Type File -Path $PROFILE -Force | Out-Null
}

# 4) Install/update wrapper in profile (idempotent)
$profileText = Get-Content $PROFILE -Raw
$begin = "# BEGIN CODEX WSL WRAPPER"
$end   = "# END CODEX WSL WRAPPER"
$wrapper = @"
$begin
function Convert-ToWslPath([string]\$winPath) {
  if (\$winPath -match '^[A-Za-z]:\\') {
    \$drive = \$winPath.Substring(0,1).ToLower()
    \$rest  = \$winPath.Substring(2).Replace('\','/')
    "/mnt/\$drive\$rest"
  } else { \$winPath }
}
function codex {
  param([Parameter(ValueFromRemainingArguments=\$true)] \$Args)
  \$win = \$PWD.Path
  \$lin = Convert-ToWslPath \$win
  wsl --cd "\$lin" codex @Args
}
$end
"@

if ($profileText -match [regex]::Escape($begin) -and $profileText -match [regex]::Escape($end)) {
  $newProfile = $profileText -replace "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))", $wrapper
} else {
  $newProfile = ($profileText.TrimEnd() + "`r`n`r`n" + $wrapper)
}
Set-Content -Path $PROFILE -Value $newProfile -Encoding UTF8

# 5) Reload profile
. $PROFILE

# 6) Smoke tests
Write-Host "PowerShell profile:" -ForegroundColor Cyan
Write-Host $PROFILE
Write-Host "`nCodex in WSL:" -ForegroundColor Cyan
wsl bash -lc 'which codex && codex --version || true'
Write-Host "`nTry from this folder:" -ForegroundColor Cyan
Write-Host "codex"
