# =====================================================================
#  night-fix :: fix-st.ps1
#  Installs the updated Steam fix files automatically.
#  Source of truth: https://github.com/night-ua/steam-fix
# =====================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Windows PowerShell 5.1 may negotiate TLS 1.0 by default, which the CDN
# rejects (handshake closed mid-send). Raise the floor so that every
# request can complete against modern servers.
try {
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor
        [System.Net.SecurityProtocolType]::Tls12 -bor
        [System.Net.SecurityProtocolType]::Tls13
} catch {
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor
        [System.Net.SecurityProtocolType]::Tls12
}

# ---------------------------------------------------------------------
# Runs one pipeline step behind a tiny spinner, then prints the outcome:
#   ok   -> green check + step label (+ optional "Location:" line)
#   fail -> red X + step label, the reason, then the script exits.
# A step scriptblock must return one of:
#   @{ Success = $true;  Path  = '<status text or file location>' }
#   @{ Success = $false; Extra = '<failure reason>' }
# ---------------------------------------------------------------------
function Invoke-Step {
    param (
        [string]$Label,
        [ScriptBlock]$Worker,
        [string]$Location = $null,
        [string]$Hint = $null
    )
    $topLine = [Console]::CursorTop
    $frames = @('|', '/', '-', '\')
    Write-Host $frames[0] -NoNewline -ForegroundColor White
    Write-Host " $Label" -ForegroundColor White
    if ($Hint) {
        $hintLine = [Console]::CursorTop
        Write-Host "  $([char]0x2514)$([char]0x2500) $Hint" -ForegroundColor Yellow
    }
    $finished = $false
    $tick = 0
    $outcome = $null
    $job = Start-Job -ScriptBlock $Worker

    while (-not $finished) {
        Start-Sleep -Milliseconds 100
        $frame = $frames[$tick % $frames.Count]
        [Console]::SetCursorPosition(0, $topLine)
        Write-Host $frame -NoNewline -ForegroundColor White
        Write-Host " $Label" -NoNewline -ForegroundColor White
        $tick++
        if ($job.State -in 'Completed', 'Failed', 'Stopped') {
            $finished = $true
        }
    }
    $outcome = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job | Out-Null

    [Console]::SetCursorPosition(0, $topLine)
    [Console]::Write((' ' * ([Console]::WindowWidth - 1)))
    if ($Hint) {
        [Console]::SetCursorPosition(0, $hintLine)
        [Console]::Write((' ' * ([Console]::WindowWidth - 1)))
    }
    [Console]::SetCursorPosition(0, $topLine)
    if ($outcome -and $outcome.Success) {
        Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
        Write-Host " $Label" -NoNewline -ForegroundColor Green
        [Console]::WriteLine('')
        if ($Location) {
            Write-Host "Location: $($outcome.Path)" -ForegroundColor White
        }
    } else {
        Write-Host 'X' -NoNewline -ForegroundColor Red
        Write-Host " $Label" -NoNewline -ForegroundColor Red
        [Console]::WriteLine('')
        if ($outcome -and $outcome.Extra) {
            Write-Host ''
            Write-Host $UiRule -ForegroundColor DarkRed
            Write-Host "  ERROR :: $($outcome.Extra)" -ForegroundColor Red
            Write-Host $UiRule -ForegroundColor DarkRed
        }
        Write-Host ''
        Write-Host 'Press any key to exit...' -ForegroundColor White
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit
    }
    return $outcome.Path
}

Clear-Host
Write-Host ''

# ---------------------------------------------------------------------
# Banner :: build "NIGHT FIX" from fixed-width block glyphs so every
# letter lines up on every row, then print it in true orange
# (ANSI 24-bit). Falls back to DarkYellow when ANSI is unavailable.
# ---------------------------------------------------------------------
$script:OrangeMode = 'fallback'   # ansi | palette | fallback
$Esc = [char]27
$OrangeCode = "$Esc[38;2;255;165;0m"
$ResetCode = "$Esc[0m"
try {
    Add-Type -Namespace 'Win32' -Name 'ConsoleFx' -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr hConsoleHandle, uint dwMode);
[StructLayout(LayoutKind.Sequential)]
public struct COORD { public short X; public short Y; }
[StructLayout(LayoutKind.Sequential)]
public struct SMALL_RECT { public short Left; public short Top; public short Right; public short Bottom; }
[StructLayout(LayoutKind.Sequential)]
public struct CONSOLE_SCREEN_BUFFER_INFOEX
{
    public uint cbSize;
    public COORD dwSize;
    public COORD dwCursorPosition;
    public ushort wAttributes;
    public SMALL_RECT srWindow;
    public COORD dwMaximumWindowSize;
    public ushort wPopupAttributes;
    [MarshalAs(UnmanagedType.Bool)] public bool bFullscreenSupported;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)] public uint[] ColorTable;
}
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleScreenBufferInfoEx(System.IntPtr h, ref CONSOLE_SCREEN_BUFFER_INFOEX info);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleScreenBufferInfoEx(System.IntPtr h, ref CONSOLE_SCREEN_BUFFER_INFOEX info);
'@
    $Native = [Win32.ConsoleFx]
    $stdOut = $Native::GetStdHandle(-11)
    $mode = [uint32]0
    $vtOn = $Native::GetConsoleMode($stdOut, [ref]$mode) -and $Native::SetConsoleMode($stdOut, ($mode -bor 4))

    if ($env:WT_SESSION -and $vtOn) {
        # Windows Terminal renders 24-bit ANSI colours natively.
        $script:OrangeMode = 'ansi'
    } else {
        # The classic console quantises ANSI colours to its 16-entry
        # palette, so repaint the DarkYellow slot with real orange.
        $info = New-Object 'Win32.ConsoleFx+CONSOLE_SCREEN_BUFFER_INFOEX'
        $info.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type]'Win32.ConsoleFx+CONSOLE_SCREEN_BUFFER_INFOEX')
        $info.ColorTable = [uint32[]]::new(16)
        if ($vtOn -and $Native::GetConsoleScreenBufferInfoEx($stdOut, [ref]$info)) {
            $info.ColorTable[6] = [uint32]0x0000A5FF   # COLORREF 0x00bbggrr -> #FFA500
            if ($Native::SetConsoleScreenBufferInfoEx($stdOut, [ref]$info)) {
                $script:OrangeMode = 'palette'
            }
        }
    }
} catch { }

# Prints text in real orange on every console flavour.
function Write-Orange {
    param([string]$Text)
    if ($script:OrangeMode -eq 'ansi') {
        Write-Host "$OrangeCode$Text$ResetCode"
    } else {
        Write-Host $Text -ForegroundColor DarkYellow
    }
}

$Glyphs = @{
    N = @('██     ██', '███    ██', '██ ██  ██', '██  ██ ██', '██     ██')
    I = @('█████', '  ██ ', '  ██ ', '  ██ ', '█████')
    G = @(' ██████ ', '██      ', '██  ████', '██    ██', ' ██████ ')
    H = @('██    ██', '██    ██', '████████', '██    ██', '██    ██')
    T = @('█████████', '   ██    ', '   ██    ', '   ██    ', '   ██    ')
    F = @('███████', '██     ', '██████ ', '██     ', '██     ')
    X = @('██   ██', ' ██ ██ ', '  ███  ', ' ██ ██ ', '██   ██')
}

$WindowCols = 80
try { $WindowCols = [Console]::WindowWidth } catch { }

# Draws one word of the banner, one glyph row at a time.
function Show-WordBanner {
    param([string]$Word)
    for ($row = 0; $row -lt 5; $row++) {
        Write-Orange ((($Word.ToCharArray() | ForEach-Object { $Glyphs[[string]$_][$row] }) -join ' '))
    }
}

Write-Host ''
if ($WindowCols -ge 70) {
    # Wide console: "NIGHT FIX" on one line per glyph row.
    for ($row = 0; $row -lt 5; $row++) {
        $left = ('NIGHT'.ToCharArray() | ForEach-Object { $Glyphs[[string]$_][$row] }) -join ' '
        $right = ('FIX'.ToCharArray() | ForEach-Object { $Glyphs[[string]$_][$row] }) -join ' '
        Write-Orange "$left   $right"
    }
} elseif ($WindowCols -ge 46) {
    # Narrow console: stack the words so nothing wraps.
    Show-WordBanner 'NIGHT'
    Write-Host ''
    Show-WordBanner 'FIX'
} else {
    # Too narrow for block letters at all.
    Write-Orange 'night-fix'
}

Write-Host ''
Write-Orange '  night-fix  ::  installs the updated Steam fix files'
Write-Host '  https://github.com/night-ua/steam-fix' -ForegroundColor DarkGray
Write-Host ''
$UiRule = [string][char]0x2500 * 66
Write-Host $UiRule -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------
# Step 0 :: locate the Steam installation through the registry
# ---------------------------------------------------------------
$SteamPath = Invoke-Step -Label '[1/9] Locate Steam installation' -Worker {
    foreach ($key in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\Software\Valve\Steam',
        'HKLM:\Software\WOW6432Node\Valve\Steam'
    )) {
        if (Test-Path $key) {
            $installDir = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).InstallPath
            if ($installDir -and (Test-Path $installDir)) {
                return @{ Success = $true; Path = $installDir }
            }
        }
    }
    return @{ Success = $false; Extra = 'Steam installation not found. Try reinstalling Steam' }
}

# ---------------------------------------------------------------
# Step 1 :: terminate every running Steam process
# ---------------------------------------------------------------
$null = Invoke-Step -Label '[2/9] Stop Steam processes' -Worker {
    $running = Get-Process | Where-Object { $_.Name -match 'steam' }
    if (-not $running) { return @{ Success = $true; Path = '' } }
    try {
        $running | Stop-Process -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        return @{ Success = $true; Path = '' }
    } catch {
        return @{ Success = $false; Extra = 'Could not terminate Steam processes. Run PowerShell as administrator and run the script again.' }
    }
}

# ---------------------------------------------------------------
# Step 2 :: delete the stale injector DLLs before replacing them
# ---------------------------------------------------------------
$null = Invoke-Step -Label '[3/9] Delete stale DLL files' -Worker {
    $sp = $using:SteamPath
    try {
        foreach ($name in @('xinput1_4.dll', 'dwmapi.dll')) {
            $target = Join-Path $sp $name
            if (Test-Path $target) { Remove-Item $target -Force -ErrorAction Stop }
        }
        return @{ Success = $true; Path = '' }
    } catch {
        return @{ Success = $false; Extra = "Could not delete files: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------
# Step 3 :: remove leftovers of the old SteamProof manifest fix
# ---------------------------------------------------------------
$null = Invoke-Step -Label '[4/9] Remove SteamProof manifest fix' -Worker {
    $sp = $using:SteamPath
    $leftovers = @(
        (Join-Path $sp 'wtsapi32.dll'),
        (Join-Path $sp 'version.dll'),
        (Join-Path $sp 'config\manifests.dll'),
        (Join-Path $sp 'config\.mfx_init'),
        (Join-Path $sp 'config\.stfix_init')
    )
    try {
        $removed = 0
        foreach ($leftover in $leftovers) {
            if (Test-Path $leftover) {
                Remove-Item $leftover -Force -ErrorAction Stop
                $removed++
            }
        }
        return @{ Success = $true; Path = "$removed file(s) removed" }
    } catch {
        return @{ Success = $false; Extra = "Could not remove SteamProof manifest fix: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------
# Transfer HUD :: throttled spinner + progress bar shown during download.
# ---------------------------------------------------------------------
function Show-TransferHud {
    param($Hud, $Title = '[5/9] Download updated files')

    $elapsed = $Hud.Clock.ElapsedMilliseconds
    if (($elapsed - $Hud.LastFrameMs) -lt 100) { return }
    $Hud.LastFrameMs = $elapsed
    $Hud.Frame++

    $frame = $Hud.Frames[$Hud.Frame % $Hud.Frames.Count]
    [Console]::SetCursorPosition(0, $Hud.TitlePos)
    [Console]::Write("$frame $Title")

    if ($Hud.TotalReady -and $Hud.TotalBytes -gt 0) {
        $ratio = [math]::Min(1.0, ($Hud.DoneBytes / $Hud.TotalBytes))
        $pct = [math]::Floor($ratio * 100)
        $filled = [math]::Floor($ratio * $Hud.BarLength)
        $bar = ("$([char]0x2588)" * $filled) + ("$([char]0x2591)" * ($Hud.BarLength - $filled))
        $doneMB = '{0:N1}' -f ($Hud.DoneBytes / 1MB)
        $totalMB = '{0:N1}' -f ($Hud.TotalBytes / 1MB)
        $barText = "  $bar $pct% ($doneMB / $totalMB MB)  "
        [Console]::SetCursorPosition(0, $Hud.BarPos)
        [Console]::Write($barText)
    }
    [Console]::SetCursorPosition(0, $Hud.TitlePos)
}

# ---------------------------------------------------------------------
# Waits for one async I/O operation while keeping the HUD alive.
# Aborts the request when the operation outlives its timeout.
# ---------------------------------------------------------------------
function Wait-Transfer {
    param(
        [IAsyncResult]$Operation,
        $Hud,
        [System.Net.HttpWebRequest]$Request,
        [int]$TimeoutMs
    )
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Operation.AsyncWaitHandle.WaitOne(100)) {
        Show-TransferHud $Hud
        if ($watch.ElapsedMilliseconds -ge $TimeoutMs) {
            $Request.Abort()
            throw 'The download request timed out.'
        }
    }
    Show-TransferHud $Hud
}

# ---------------------------------------------------------------
# Step 4 :: download the updated fix files straight from the
#           repository: https://github.com/night-ua/steam-fix
# ---------------------------------------------------------------
$RepoRawBase = 'https://raw.githubusercontent.com/night-ua/steam-fix/main/'
$FixFileNames = @(
    'dwmapi.dll',
    'dwmapi.exp',
    'dwmapi.lib',
    'lua_static.lib',
    'OpenSteamTool.dll',
    'xinput1_4.dll',
    'xinput1_4.exp',
    'xinput1_4.lib'
)
$FixFiles = $FixFileNames | ForEach-Object { @{ Name = $_; Url = $RepoRawBase + $_ } }

$frames = @('|', '/', '-', '\')
$hudTop = [Console]::CursorTop
Write-Host "$($frames[0]) [5/9] Download updated files" -ForegroundColor White
$barTop = [Console]::CursorTop
Write-Host ''
$hud = @{
    TitlePos    = $hudTop
    BarPos      = $barTop
    BarLength   = 30
    Frames      = $frames
    Frame       = 0
    LastFrameMs = -100
    DoneBytes   = 0L
    TotalBytes  = 0L
    TotalReady  = $false
    Clock       = [Diagnostics.Stopwatch]::StartNew()
}

$downloadsOk = $false
$headResp = $null
$bodyResp = $null
$body = $null
$outFile = $null
$item = $null

try {
    # Pass 1 :: HEAD every file so the bar can show real totals.
    foreach ($entry in $FixFiles) {
        $request = [System.Net.HttpWebRequest]::Create($entry.Url)
        $request.Method = 'HEAD'
        $head = $request.BeginGetResponse($null, $null)
        Wait-Transfer $head $hud $request $request.Timeout
        $headResp = $request.EndGetResponse($head)
        if ($headResp.ContentLength -gt 0) {
            $hud.TotalBytes += $headResp.ContentLength
        }
        $headResp.Close()
        $headResp = $null
    }
    $hud.TotalReady = $true

    # Pass 2 :: stream every file into the Steam directory.
    foreach ($entry in $FixFiles) {
        $item = $entry
        $dest = Join-Path $SteamPath $entry.Name
        $request = [System.Net.HttpWebRequest]::Create($entry.Url)
        $async = $request.BeginGetResponse($null, $null)
        Wait-Transfer $async $hud $request $request.Timeout
        $bodyResp = $request.EndGetResponse($async)
        $body = $bodyResp.GetResponseStream()
        $outFile = [System.IO.File]::Create($dest)
        $chunk = New-Object byte[] 8192

        while ($true) {
            $pending = $body.BeginRead($chunk, 0, $chunk.Length, $null, $null)
            Wait-Transfer $pending $hud $request $request.ReadWriteTimeout
            $read = $body.EndRead($pending)
            if ($read -eq 0) { break }
            $outFile.Write($chunk, 0, $read)
            $hud.DoneBytes += $read
            Show-TransferHud $hud
        }

        $outFile.Close();  $outFile = $null
        $body.Close();     $body = $null
        $bodyResp.Close(); $bodyResp = $null
    }
    $downloadsOk = $true
} catch {
    $downloadError = $_
    $failedName = if ($item) { $item.Name } else { 'unknown' }
    if ($headResp) { $headResp.Close() }
    if ($outFile)  { $outFile.Close() }
    if ($body)     { $body.Close() }
    if ($bodyResp) { $bodyResp.Close() }
}

[Console]::SetCursorPosition(0, $hudTop)
[Console]::Write((' ' * ([Console]::WindowWidth - 1)))
[Console]::SetCursorPosition(0, $barTop)
[Console]::Write((' ' * ([Console]::WindowWidth - 1)))
[Console]::SetCursorPosition(0, $hudTop)
if ($downloadsOk) {
    Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
    Write-Host ' [5/9] Download updated files' -ForegroundColor Green
} else {
    Write-Host 'X' -NoNewline -ForegroundColor Red
    Write-Host ' [5/9] Download updated files' -ForegroundColor Red
    $reason = "Failed to download $failedName"
    if ($downloadError.Exception -is [System.Net.WebException] -and $downloadError.Exception.Response) {
        $code = [int]$downloadError.Exception.Response.StatusCode
        $desc = $downloadError.Exception.Response.StatusDescription
        $reason += " (HTTP $code $desc)"
    } elseif ($downloadError.Exception) {
        $reason += ": $($downloadError.Exception.Message)"
    }
    Write-Host ''
    Write-Host $UiRule -ForegroundColor DarkRed
    Write-Host "  ERROR :: $reason" -ForegroundColor Red
    Write-Host $UiRule -ForegroundColor DarkRed
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor White
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

# ---------------------------------------------------------------
# Step 6 :: point opensteamtool.toml at the correct GMRC source.
#           Flips steamrun -> wudrm when the old config used steamrun.
# ---------------------------------------------------------------
$null = Invoke-Step -Label '[6/9] Configure GMRC source' -Worker {
    $configFile = Join-Path $using:SteamPath 'opensteamtool.toml'
    try {
        $source = 'steamrun'
        if (Test-Path -LiteralPath $configFile) {
            $inManifest = $false
            foreach ($line in [System.IO.File]::ReadAllLines($configFile)) {
                if ($line -match '^\s*\[([^\]]+)\]\s*(?:#.*)?$') {
                    $inManifest = $Matches[1] -eq 'manifest'
                    continue
                }
                if ($inManifest -and $line -match '^\s*url\s*=\s*"(steamrun|wudrm)"\s*(?:#.*)?$') {
                    if ($Matches[1] -eq 'steamrun') { $source = 'wudrm' }
                    break
                }
            }
        }
        [System.IO.File]::WriteAllText(
            $configFile,
            "[manifest]`r`nurl = `"$source`"`r`n",
            [System.Text.UTF8Encoding]::new($false)
        )
        return @{ Success = $true; Path = $configFile }
    } catch {
        return @{ Success = $false; Extra = "Could not configure GMRC source: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------
# Step 7 :: move existing lua plug-ins into config\lua
# ---------------------------------------------------------------
$null = Invoke-Step -Label '[7/9] Move lua files' -Worker {
    $sp = $using:SteamPath
    $fromDir = Join-Path $sp 'config\stplug-in'
    $toDir = Join-Path $sp 'config\lua'
    try {
        if (-not (Test-Path $toDir)) {
            $null = New-Item -Path $toDir -ItemType Directory -Force -ErrorAction Stop
        }
        if (-not (Test-Path $fromDir)) { return @{ Success = $true; Path = '0 file(s) moved' } }
        $moved = 0
        foreach ($file in Get-ChildItem -Path $fromDir -Filter '*.lua' -ErrorAction SilentlyContinue) {
            Move-Item -Path $file.FullName -Destination (Join-Path $toDir $file.Name) -Force -ErrorAction Stop
            $moved++
        }
        return @{ Success = $true; Path = "$moved file(s) moved" }
    } catch {
        return @{ Success = $false; Extra = "Could not move lua files: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------
# Step 8 :: strip legacy SteamProof lines out of the lua files
# ---------------------------------------------------------------
$null = Invoke-Step -Label '[8/9] Clean lua files' -Worker {
    $luaDir = Join-Path $using:SteamPath 'config\lua'
    if (-not (Test-Path $luaDir)) { return @{ Success = $true; Path = '' } }
    $cleaned = 0
    foreach ($file in Get-ChildItem -Path $luaDir -Filter '*.lua' -ErrorAction SilentlyContinue) {
        $raw = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($raw -notmatch 'SteamProof') { continue }
        $kept = Get-Content $file.FullName |
            Where-Object { $_ -notmatch '^-- SteamProof' -and $_ -notmatch '^setManifestid' }
        while ($kept.Count -gt 0 -and $kept[-1].Trim() -eq '') {
            $kept = $kept[0..($kept.Count - 2)]
        }
        $kept | Set-Content $file.FullName -Encoding UTF8
        $cleaned++
    }
    return @{ Success = $true; Path = "$cleaned file(s) cleaned" }
}

# ---------------------------------------------------------------
# Step 9 :: remove the UTF-8 BOM that breaks lua parsing
# ---------------------------------------------------------------
$null = Invoke-Step -Label '[9/9] Fix lua files' -Worker {
    $luaDir = Join-Path $using:SteamPath 'config\lua'
    if (-not (Test-Path $luaDir)) { return @{ Success = $true; Path = '' } }
    $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
    $fixed = 0
    foreach ($file in Get-ChildItem -Path $luaDir -Filter '*.lua' -ErrorAction SilentlyContinue) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq $bom[0] -and $bytes[1] -eq $bom[1] -and $bytes[2] -eq $bom[2]) {
            [System.IO.File]::WriteAllBytes($file.FullName, $bytes[3..($bytes.Length - 1)])
            $fixed++
        }
    }
    return @{ Success = $true; Path = "$fixed file(s) fixed" }
}

# ---------------------------------------------------------------------
# Done :: final instructions for the user.
# ---------------------------------------------------------------------
Write-Host ''
Write-Host $UiRule -ForegroundColor Green
Write-Host " $([char]0x2713) Process completed -- all steps finished" -ForegroundColor Green
Write-Host $UiRule -ForegroundColor Green
Write-Host ''
Write-Host 'To add games or apps:' -ForegroundColor Yellow
Write-Host 'Move each downloaded .lua file into this folder:' -ForegroundColor White
Write-Host "  $(Join-Path $SteamPath 'config\lua')" -ForegroundColor White
Write-Host 'Dragging files onto the floating Steam icon no longer works.' -ForegroundColor White
Write-Host 'Steam picks up files in that folder right away. No restart is needed.' -ForegroundColor White
Write-Host ''
Write-Host 'Open Steam normally and retry the download or update.' -ForegroundColor Yellow
Write-Host 'If Steam shows NO INTERNET CONNECTION or UNKNOWN ERROR:' -ForegroundColor Yellow
Write-Host '  1. Right-click the Steam icon in the system tray and choose Exit Steam.' -ForegroundColor White
Write-Host '     Open Steam normally and retry.' -ForegroundColor White
Write-Host '  2. If it still fails, run this script again.' -ForegroundColor White
Write-Host '     Open Steam normally and retry.' -ForegroundColor White
Write-Host '  3. If it still fails, exit Steam from the tray and open it normally again.' -ForegroundColor White
Write-Host '     Retry the download or update.' -ForegroundColor White
Write-Host ''
Write-Host 'Press any key to exit...' -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
exit