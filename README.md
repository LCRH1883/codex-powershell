# Codex on PowerShell via WSL

This repository provides `Setup-Codex.ps1`, a one-time PowerShell script that installs Node.js 22 and the `@openai/codex` CLI inside your default Ubuntu WSL instance, then adds a PowerShell wrapper so you can run `codex` from any Windows folder.

## Prerequisites
- Windows 10/11 with [WSL 2](https://learn.microsoft.com/windows/wsl/install) enabled and an Ubuntu distro installed as the default.
- PowerShell (Windows PowerShell 5.1 or PowerShell 7+).
- Internet access for `apt`, `curl`, and `npm` downloads.

> Tip: Run `wsl --status` in PowerShell to confirm WSL is installed and Ubuntu is the default distribution before starting.

## Quick Start
1. Download or clone this repository so that `Setup-Codex.ps1` is on your machine.
2. Open a new **non-admin** PowerShell window in the folder that contains the script.
3. Allow the script to run in the current session (if execution policy blocks it):
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   ```
4. Execute the installer:
   ```powershell
   .\Setup-Codex.ps1
   ```
5. Restart PowerShell (or open a new window) and run `codex --version` from any Windows path to confirm the wrapper works.

The script is idempotent — re-run it any time you want to upgrade Codex or refresh the wrapper.

## What the Script Does
- Removes any existing Windows-side `codex` shims under `%AppData%\npm`.
- Ensures `curl`, `ca-certificates`, `gnupg` are present in Ubuntu.
- Installs Node.js 22 via NodeSource packages (no NVM), and installs `@openai/codex` globally.
- Injects a `codex` function into your PowerShell profile that transparently forwards calls into WSL with the correct working directory.
- Reloads your PowerShell profile and prints a quick status check.

## After Installation
- From any Windows folder, run `codex` and the command will execute inside Ubuntu WSL.
- Inside WSL you can manage Codex with `npm` as usual (e.g., `npm update -g @openai/codex`).
- The wrapper function lives inside your PowerShell profile (`$PROFILE`) between `# BEGIN/END CODEX WSL WRAPPER`. You can remove or adjust it later if needed.

## Troubleshooting
- **WSL not installed**: The script stops if `wsl --status` fails. Follow the [WSL installation guide](https://learn.microsoft.com/windows/wsl/install) and ensure Ubuntu is the default distribution.
- **`sudo` prompts**: Package installs inside Ubuntu require your Linux user password. Enter it when prompted.
- **Missing profile directory**: The script creates the profile file automatically, but PowerShell must have permission to write to it. If it fails, check `$PROFILE`.
- **`codex` not found afterwards**: Open a new PowerShell window so the updated profile loads, or run `. $PROFILE` manually.
  If you installed a different WSL distro than Ubuntu as default, the wrapper targets your default distro automatically.
- **Proxy or firewall issues**: `curl`, `apt`, or `npm` might need proxy configuration. Configure your environment variables accordingly before re-running the script.

Need to undo the wrapper? Remove the `# BEGIN CODEX WSL WRAPPER` block from your PowerShell profile and delete any global Codex install inside Ubuntu (`sudo npm uninstall -g @openai/codex`).

### Legacy scripts
- `Setup-CodexWSL.ps1` and `Setup-DevPS-CodexWrapper.ps1` are deprecated and now delegate to `Setup-Codex.ps1` for a unified flow.
