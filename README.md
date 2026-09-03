# Steam Fix

A PowerShell utility that installs the required Steam fix files automatically.

> [!WARNING]
> You must run PowerShell as Administrator. The script may fail to stop Steam or replace files in the Steam installation directory without administrator privileges.

## Quick install

Close any important work, right-click PowerShell, select **Run as administrator**, and then run:

```powershell
irm https://raw.githubusercontent.com/night-ua/steam-fix/main/fix-st.ps1 | iex
```

The expanded form of the same command is:

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/night-ua/steam-fix/main/fix-st.ps1 | Invoke-Expression
```

## What the script does

- Finds the Steam installation directory.
- Stops running Steam processes.
- Removes old or conflicting fix files.
- Downloads the updated files from this repository.
- Moves existing Lua plug-ins to `config\lua`.
- Cleans legacy SteamProof entries and removes UTF-8 BOMs from Lua files.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- An existing Steam installation
- An active internet connection
- Administrator privileges if Steam is installed in a protected directory

## Security note

The quick-install command downloads and executes the latest version of the script directly from this repository. Review [`fix-st.ps1`](./fix-st.ps1) before running it if you want to inspect the actions it performs.

## Manual installation

1. Download or clone this repository.
2. Open PowerShell as Administrator in the downloaded directory.
3. Run:

```powershell
.\fix-st.ps1
```

If script execution is blocked for the current PowerShell process, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\fix-st.ps1
```

## License

This project is distributed under the terms of the included [MIT License](./LICENSE).
