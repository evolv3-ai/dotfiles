# IT Endpoint Bootstrap

Turn a bare Windows 10/11 PC into a Claude Code-managed IT endpoint with one command.

## Quick Start (Run as Administrator)

```powershell
irm https://raw.githubusercontent.com/evolv3-ai/dotfiles/main/bootstrap.ps1 | iex
```

Or clone and run locally:

```powershell
git clone https://github.com/evolv3-ai/dotfiles.git C:\bootstrap
cd C:\bootstrap
powershell -ExecutionPolicy Bypass -File bootstrap.ps1
```

## What It Does

1. **Installs Node.js LTS** — via winget (Win11) or direct MSI (Win10)
2. **Installs Claude Code** — `@anthropic-ai/claude-code` globally via npm
3. **Installs IT admin tools** — core winget packages for endpoint management
4. **Configures Claude Code** — IT-focused CLAUDE.md and default settings
5. **Collects system inventory** — hardware, OS, network, installed software
6. **Sets up PowerShell profile** — IT admin aliases and helper functions

## What Gets Installed

### Always (core)

| Package | Purpose |
|---|---|
| Node.js LTS | Claude Code runtime |
| Claude Code | AI-powered IT management |
| PowerShell 7+ | Modern shell |
| Git | Version control, config pulls |
| 7-Zip | Archive management |
| Windows Terminal | Better terminal experience |

### IT Admin Tools

| Package | Purpose |
|---|---|
| SysInternals Suite | Deep system diagnostics |
| TreeSize Free | Disk space analysis |
| WinSCP | Secure file transfer |
| PuTTY | SSH client |
| Everything | Instant file search |
| Nmap | Network scanning |
| Wireshark | Network diagnostics |

Pass `-SkipApps` to the bootstrap to install only Node.js + Claude Code.

## Customisation

### Add/remove winget apps

Edit `windows/Install-Apps.ps1` — apps are grouped by category. Comment out what you don't need.

### Modify Claude Code's IT instructions

Edit `claude-code/CLAUDE.md` — this becomes the system prompt for Claude Code on managed PCs.

### Change the PowerShell profile

Edit `powershell/Profile.ps1` — IT aliases and functions deployed to managed PCs.

## Structure

```
bootstrap.ps1               # Entry point (one-liner compatible)
windows/
  Install-Apps.ps1           # Winget app list (IT admin stack)
claude-code/
  install.ps1                # Node.js + Claude Code installer
  CLAUDE.md                  # IT admin instructions for Claude Code
  settings.json              # Default Claude Code settings
powershell/
  Profile.ps1                # IT admin PowerShell profile
scripts/
  Get-SystemInfo.ps1         # Hardware/software inventory
  Test-Connectivity.ps1      # Network diagnostics
```

## Requirements

- Windows 10 (build 1809+) or Windows 11
- Administrator access
- Internet connection
- Anthropic account (for Claude Code authentication)

## Security Notes

- No secrets are stored in this repo
- Claude Code authenticates via browser OAuth on first run
- The bootstrap runs only from official sources (winget, nodejs.org, npmjs.com)
- System inventory is saved locally — nothing is phoned home
