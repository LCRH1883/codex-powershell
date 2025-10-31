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

# Target profiles: current host, all hosts, Visual Studio Developer PowerShell
$profileTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in @($PROFILE.CurrentUserCurrentHost, $PROFILE.CurrentUserAllHosts)) {
  if (-not [string]::IsNullOrWhiteSpace($path)) { [void]$profileTargets.Add($path) }
}

function Add-DocRoot {
  param([string]$Path, [System.Collections.Generic.HashSet[string]]$RootSet)
  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  try {
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
  } catch {
    $expanded = $Path
  }
  if (-not [string]::IsNullOrWhiteSpace($expanded)) {
    [void]$RootSet.Add($expanded)
  }
}

$docRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
try { Add-DocRoot -Path ([Environment]::GetFolderPath('MyDocuments')) -RootSet $docRoots } catch {}
if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
  Add-DocRoot -Path (Join-Path -Path $env:USERPROFILE -ChildPath 'Documents') -RootSet $docRoots
}
foreach ($oneDriveVar in @('OneDrive', 'OneDriveCommercial', 'OneDriveConsumer')) {
  $val = Get-Item -Path "Env:$oneDriveVar" -ErrorAction SilentlyContinue
  if ($val -and -not [string]::IsNullOrWhiteSpace($val.Value)) {
    Add-DocRoot -Path (Join-Path -Path $val.Value -ChildPath 'Documents') -RootSet $docRoots
  }
}

foreach ($root in $docRoots) {
  if ([string]::IsNullOrWhiteSpace($root)) { continue }
  $vsRootProfile = Join-Path -Path $root -ChildPath 'Microsoft.VSDevShell_profile.ps1'
  [void]$profileTargets.Add($vsRootProfile)

  $psDir = Join-Path -Path $root -ChildPath 'PowerShell'
  [void]$profileTargets.Add((Join-Path -Path $psDir -ChildPath 'Microsoft.VSDevShell_profile.ps1'))
  $psHostProfile = Join-Path -Path $psDir -ChildPath 'Microsoft.PowerShell_profile.ps1'
  if (Test-Path -Path $psHostProfile) {
    [void]$profileTargets.Add($psHostProfile)
  }
  $defaultProfile = Join-Path -Path $psDir -ChildPath 'profile.ps1'
  if (Test-Path -Path $defaultProfile) {
    [void]$profileTargets.Add($defaultProfile)
  }

  try {
    if (Test-Path -Path $root) {
      $vsDirs = Get-ChildItem -Path $root -Directory -Filter 'Visual Studio*' -ErrorAction SilentlyContinue
      foreach ($vsDir in $vsDirs) {
        $vsPsDir = Join-Path -Path $vsDir.FullName -ChildPath 'PowerShell'
        [void]$profileTargets.Add((Join-Path -Path $vsPsDir -ChildPath 'Microsoft.VSDevShell_profile.ps1'))
        foreach ($name in @('Microsoft.PowerShell_profile.ps1', 'profile.ps1')) {
          $candidate = Join-Path -Path $vsPsDir -ChildPath $name
          if (Test-Path -Path $candidate) {
            [void]$profileTargets.Add($candidate)
          }
        }
      }
    }
  } catch {}
}

$updatedProfiles = @()
foreach ($profilePath in $profileTargets) {
  try {
    $parent = Split-Path -Parent $profilePath
    if (-not (Test-Path $parent)) {
      New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $existingProfile = Test-Path $profilePath
    $isWindowsPowerShell = $profilePath -match '\\WindowsPowerShell\\'
    if (-not $existingProfile -and $isWindowsPowerShell) {
      Write-Host "Skipping WindowsPowerShell profile (execution policy likely Restricted): $profilePath" -ForegroundColor DarkYellow
      continue
    }
    if (-not $existingProfile) {
      New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }
    $devText = ''
    if ($existingProfile) {
      $devText = Get-Content $profilePath -Raw
    }
    if ($null -eq $devText) { $devText = '' }
    $devText = [regex]::Replace($devText, "(?s)$([regex]::Escape($begin)).*?$([regex]::Escape($end))", '')
    $devText = [regex]::Replace($devText, '(?s)function\s+Convert-ToWslPath\s*\([^)]*\)\s*\{.*?\}', '')
    $devText = [regex]::Replace($devText, '(?s)function\s+codex\s*\{.*?\}', '')
    if (-not [string]::IsNullOrWhiteSpace($devText)) {
      $devText = $devText.TrimEnd() + "`r`n`r`n" + $wrapper
    } else {
      $devText = $wrapper
    }
    Set-Content -Path $profilePath -Value $devText -Encoding UTF8
    $updatedProfiles += $profilePath
    Write-Host "Updated Codex wrapper in profile: $profilePath" -ForegroundColor DarkGray
  } catch {
    Write-Warning "Failed to update profile '$profilePath': $_"
  }
}

# 4) Reload and confirm for the current host profile (if updated)
$currentProfile = $PROFILE.CurrentUserCurrentHost
if ($currentProfile -and ($updatedProfiles -contains $currentProfile) -and (Test-Path $currentProfile)) {
  . $currentProfile
}
Write-Host "Profile(s) updated:" -ForegroundColor Cyan
foreach ($path in $updatedProfiles) {
  Write-Host " - $path" -ForegroundColor Cyan
}
Write-Host "Run: Get-Command codex; codex --version" -ForegroundColor Cyan
