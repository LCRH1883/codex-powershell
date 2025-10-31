# Setup-DevPS-CodexWrapper.ps1
$ErrorActionPreference = "Stop"

# 0) Resolve Developer PowerShell profile (current host only)
$devProfile = $PROFILE.CurrentUserCurrentHost
if (!(Test-Path $devProfile)) {
  New-Item -ItemType File -Path $devProfile -Force | Out-Null
}

# 1) Detect default WSL distro (fallback: Ubuntu)
$distro = ""
try {
  $status = wsl --status 2>$null
  if ($status) {
    $m = [regex]::Match($status, "Default Distribution:\s*(.+)$", "Multiline")
    if ($m.Success) { $distro = $m.Groups[1].Value.Trim() }
  }
} catch {}
if ([string]::IsNullOrWhiteSpace($distro)) { $distro = "Ubuntu" }

# 2) Wrapper block to insert/replace
$begin = "# BEGIN CODEX WSL WRAPPER"
$end   = "# END CODEX WSL WRAPPER"
# Use a single-quoted here-string so $ variables are not expanded at assignment time.
# Insert the resolved distro via a literal placeholder to avoid String.Format conflicts with braces.
$wrapper = @'
# BEGIN CODEX WSL WRAPPER
function Convert-ToWslPath([string]$winPath) {
  if ($winPath -match "^[A-Za-z]:\\") {
    $drive = $winPath.Substring(0,1).ToLower()
    $rest  = $winPath.Substring(2).Replace("\\","/")
    "/mnt/$drive$rest"
  } else { $winPath }
}
function codex {
  param([Parameter(ValueFromRemainingArguments=$true)] $Args)
  $lin = Convert-ToWslPath $PWD.Path
  # Load nvm in WSL so Codex is on PATH even in non-interactive shells.
  wsl -d "___DISTRO___" --cd "$lin" bash -lc 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; codex "$@"' -- @Args
}
# END CODEX WSL WRAPPER
'@
$wrapper = $wrapper.Replace('___DISTRO___', $distro)

# 3) Insert or replace in Developer PowerShell profile
$devText = Get-Content $devProfile -Raw
$regex = "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))"
if ($devText -match $regex) {
  $devText = [regex]::Replace($devText, $regex, $wrapper)
} else {
  $devText = ($devText.TrimEnd() + "`r`n`r`n" + $wrapper)
}
Set-Content -Path $devProfile -Value $devText -Encoding UTF8

# 4) Reload and confirm
. $devProfile
Write-Host "Developer PowerShell profile updated:" -ForegroundColor Cyan
Write-Host $devProfile
Write-Host "`nTest now: 'codex' in any Windows folder." -ForegroundColor Cyan

