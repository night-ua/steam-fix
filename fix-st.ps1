[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Windows PowerShell 5.1 may default to TLS 1.0, which the CDN rejects (handshake
# closed mid-send). Force modern TLS so HttpWebRequest can negotiate with the server.
try {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol `
        -bor [System.Net.SecurityProtocolType]::Tls12 `
        -bor [System.Net.SecurityProtocolType]::Tls13
} catch {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol `
        -bor [System.Net.SecurityProtocolType]::Tls12
}

function Show-SpinnerAndResult {
    param (
        [string]$SpinnerText,
        [ScriptBlock]$Action,
        [string]$ExtraInfo = $null,
        [string]$Tip = $null
    )
    $spinnerPos = [Console]::CursorTop
    $spinner = @('|', '/', '-', '\')
    Write-Host $spinner[0] -NoNewline -ForegroundColor White
    Write-Host " $SpinnerText" -ForegroundColor White
    if ($Tip) {
        $tipPos = [Console]::CursorTop
        Write-Host "  $([char]0x2514)$([char]0x2500) $Tip" -ForegroundColor Yellow
    }
    $done = $false
    $i = 0
    $result = $null
    $job = Start-Job -ScriptBlock $Action

    while (-not $done) {
        Start-Sleep -Milliseconds 100
        $char = $spinner[$i % $spinner.Count]
        [Console]::SetCursorPosition(0, $spinnerPos)
        Write-Host $char -NoNewline -ForegroundColor White
        Write-Host " $SpinnerText" -NoNewline -ForegroundColor White
        $i++
        if ($job.State -eq 'Completed' -or $job.State -eq 'Failed' -or $job.State -eq 'Stopped') {
            $done = $true
        }
    }
    $result = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job | Out-Null

    [Console]::SetCursorPosition(0, $spinnerPos)
    [Console]::Write((' ' * ([Console]::WindowWidth-1)))
    if ($Tip) {
        [Console]::SetCursorPosition(0, $tipPos)
        [Console]::Write((' ' * ([Console]::WindowWidth-1)))
    }
    [Console]::SetCursorPosition(0, $spinnerPos)
    if ($result -and $result.Success) {
        Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
        Write-Host " $SpinnerText" -NoNewline -ForegroundColor Green
        [Console]::WriteLine('')
        if ($ExtraInfo) {
            Write-Host "Location: $($result.Path)" -ForegroundColor White
        }
    } else {
        Write-Host 'X' -NoNewline -ForegroundColor Red
        Write-Host " $SpinnerText" -NoNewline -ForegroundColor Red
        [Console]::WriteLine('')
        if ($result -and $result.Extra) {
            Write-Host "$($result.Extra)" -ForegroundColor Red
        }
        Write-Host ''
        Write-Host 'Press any key to exit...' -ForegroundColor White
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit
    }
    return $result.Path
}


# Step 0: Find Steam installation
$steamPath = Show-SpinnerAndResult `
    -SpinnerText 'Find Steam installation' `
    -Action {
        $registryPaths = @(
            'HKCU:\Software\Valve\Steam',
            'HKLM:\Software\Valve\Steam',
            'HKLM:\Software\WOW6432Node\Valve\Steam'
        )

        foreach ($regPath in $registryPaths) {
            if (Test-Path $regPath) {
                $installPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
                if ($installPath -and (Test-Path $installPath)) {
                    return @{ Success = $true; Path = $installPath }
                }
            }
        }

        return @{ Success = $false; Extra = 'Steam installation not found. Try reinstalling Steam' }
    }

# Step 1: Kill Steam processes
$null = Show-SpinnerAndResult `
    -SpinnerText 'Kill all Steam processes' `
    -Action {
        $steamProcesses = Get-Process | Where-Object { $_.Name -match 'steam' }

        if ($steamProcesses) {
            try {
                $steamProcesses | Stop-Process -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
                return @{ Success = $true; Path = '' }
            } catch {
                return @{ Success = $false; Extra = "Could not terminate Steam processes. Run PowerShell as administrator and run the script again." }
            }
        } else {
            return @{ Success = $true; Path = '' }
        }
    }

# Step 2: Delete existing xinput1_4.dll and dwmapi.dll
$null = Show-SpinnerAndResult `
    -SpinnerText 'Delete old files' `
    -Action {
        $dll1 = Join-Path $using:steamPath 'xinput1_4.dll'
        $dll2 = Join-Path $using:steamPath 'dwmapi.dll'

        try {
            if (Test-Path $dll1) { Remove-Item $dll1 -Force -ErrorAction Stop }
            if (Test-Path $dll2) { Remove-Item $dll2 -Force -ErrorAction Stop }
            return @{ Success = $true; Path = '' }
        } catch {
            return @{ Success = $false; Extra = "Could not delete files: $($_.Exception.Message)" }
        }
    }

# Step 3: Remove the SteamProof manifest fix
$null = Show-SpinnerAndResult `
    -SpinnerText 'Remove SteamProof manifest fix' `
    -Action {
        $sp = $using:steamPath
        $targets = @(
            (Join-Path $sp 'wtsapi32.dll'),
            (Join-Path $sp 'version.dll'),
            (Join-Path $sp 'config\manifests.dll'),
            (Join-Path $sp 'config\.mfx_init'),
            (Join-Path $sp 'config\.stfix_init')
        )

        try {
            $removed = 0
            foreach ($t in $targets) {
                if (Test-Path $t) {
                    Remove-Item $t -Force -ErrorAction Stop
                    $removed++
                }
            }
            return @{ Success = $true; Path = "$removed file(s) removed" }
        } catch {
            return @{ Success = $false; Extra = "Could not remove SteamProof manifest fix: $($_.Exception.Message)" }
        }
    }

function Update-DownloadDisplay {
    param($Display)

    $elapsed = $Display.Clock.ElapsedMilliseconds
    if (($elapsed - $Display.LastFrameMs) -lt 100) { return }
    $Display.LastFrameMs = $elapsed
    $Display.Frame++

    $char = $Display.Spinner[$Display.Frame % $Display.Spinner.Count]
    [Console]::SetCursorPosition(0, $Display.TitlePos)
    [Console]::Write("$char Download updated files")

    if ($Display.TotalReady -and $Display.TotalBytes -gt 0) {
        $progress = [math]::Min(1.0, ($Display.DownloadedBytes / $Display.TotalBytes))
        $pct = [math]::Floor($progress * 100)
        $filled = [math]::Floor($progress * $Display.BarLength)
        $empty = $Display.BarLength - $filled
        $bar = "$([char]0x2588)" * $filled + "$([char]0x2591)" * $empty
        $sizeMB = '{0:N1}' -f ($Display.DownloadedBytes / 1MB)
        $totalMB = '{0:N1}' -f ($Display.TotalBytes / 1MB)
        $barText = "  $bar $pct% ($sizeMB / $totalMB MB)  "
        [Console]::SetCursorPosition(0, $Display.BarPos)
        [Console]::Write($barText)
    }

    [Console]::SetCursorPosition(0, $Display.TitlePos)
}

function Wait-DownloadOperation {
    param(
        [IAsyncResult]$Operation,
        $Display,
        [System.Net.HttpWebRequest]$Request,
        [int]$TimeoutMs
    )

    $wait = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Operation.AsyncWaitHandle.WaitOne(100)) {
        Update-DownloadDisplay $Display
        if ($wait.ElapsedMilliseconds -ge $TimeoutMs) {
            $Request.Abort()
            throw 'The download request timed out.'
        }
    }
    Update-DownloadDisplay $Display
}

# Step 4: Download updated files
$dllDownloadSuccess = $false
$dllSpinner = @('|', '/', '-', '\')
$dllNames = @(
    'dwmapi.dll',
    'dwmapi.exp',
    'dwmapi.lib',
    'lua_static.lib',
    'OpenSteamTool.dll',
    'xinput1_4.dll',
    'xinput1_4.exp',
    'xinput1_4.lib'
)
$dllFiles = $dllNames | ForEach-Object { @{ Name = $_; Url = "https://raw.githubusercontent.com/night-ua/steam-fix/main/$_" } }
$dllTitlePos = [Console]::CursorTop
Write-Host "$($dllSpinner[0]) Download updated files" -ForegroundColor White
$dllBarPos = [Console]::CursorTop
Write-Host ''
$dllDisplay = @{
    TitlePos = $dllTitlePos
    BarPos = $dllBarPos
    BarLength = 30
    Spinner = $dllSpinner
    Frame = 0
    LastFrameMs = -100
    DownloadedBytes = 0L
    TotalBytes = 0L
    TotalReady = $false
    Clock = [Diagnostics.Stopwatch]::StartNew()
}

try {
    foreach ($dll in $dllFiles) {
        $req = [System.Net.HttpWebRequest]::Create($dll.Url)
        $req.Method = 'HEAD'
        $headResult = $req.BeginGetResponse($null, $null)
        Wait-DownloadOperation $headResult $dllDisplay $req $req.Timeout
        $resp = $req.EndGetResponse($headResult)
        if ($resp.ContentLength -gt 0) {
            $dllDisplay.TotalBytes += $resp.ContentLength
        }
        $resp.Close()
        $resp = $null
    }
    $dllDisplay.TotalReady = $true

    foreach ($dll in $dllFiles) {
        $outPath = Join-Path $steamPath $dll.Name
        $req = [System.Net.HttpWebRequest]::Create($dll.Url)
        $responseResult = $req.BeginGetResponse($null, $null)
        Wait-DownloadOperation $responseResult $dllDisplay $req $req.Timeout
        $response = $req.EndGetResponse($responseResult)
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($outPath)
        $buffer = New-Object byte[] 8192

        while ($true) {
            $readResult = $stream.BeginRead($buffer, 0, $buffer.Length, $null, $null)
            Wait-DownloadOperation $readResult $dllDisplay $req $req.ReadWriteTimeout
            $bytesRead = $stream.EndRead($readResult)
            if ($bytesRead -eq 0) { break }

            $fileStream.Write($buffer, 0, $bytesRead)
            $dllDisplay.DownloadedBytes += $bytesRead
            Update-DownloadDisplay $dllDisplay
        }

        $fileStream.Close()
        $fileStream = $null
        $stream.Close()
        $stream = $null
        $response.Close()
        $response = $null
    }
    $dllDownloadSuccess = $true
} catch {
    $dllError = $_
    $failedFile = if ($dll) { $dll.Name } else { 'unknown' }
    if ($resp) { $resp.Close() }
    if ($fileStream) { $fileStream.Close() }
    if ($stream) { $stream.Close() }
    if ($response) { $response.Close() }
}

[Console]::SetCursorPosition(0, $dllTitlePos)
[Console]::Write((' ' * ([Console]::WindowWidth - 1)))
[Console]::SetCursorPosition(0, $dllBarPos)
[Console]::Write((' ' * ([Console]::WindowWidth - 1)))
[Console]::SetCursorPosition(0, $dllTitlePos)
if ($dllDownloadSuccess) {
    Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
    Write-Host ' Download updated files' -ForegroundColor Green
} else {
    Write-Host 'X' -NoNewline -ForegroundColor Red
    Write-Host ' Download updated files' -ForegroundColor Red
    $errMsg = "Failed to download $failedFile"
    if ($dllError.Exception -is [System.Net.WebException] -and $dllError.Exception.Response) {
        $statusCode = [int]$dllError.Exception.Response.StatusCode
        $statusDesc = $dllError.Exception.Response.StatusDescription
        $errMsg += " (HTTP $statusCode $statusDesc)"
    } elseif ($dllError.Exception) {
        $errMsg += ": $($dllError.Exception.Message)"
    }
    Write-Host $errMsg -ForegroundColor Red
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor White
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

# Step 5: Configure GMRC source
$null = Show-SpinnerAndResult `
    -SpinnerText 'Configure GMRC source' `
    -Action {
        $configPath = Join-Path $using:steamPath 'opensteamtool.toml'

        try {
            $source = 'steamrun'
            if (Test-Path -LiteralPath $configPath) {
                $inManifest = $false
                foreach ($line in [System.IO.File]::ReadAllLines($configPath)) {
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
                $configPath,
                "[manifest]`r`nurl = `"$source`"`r`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            return @{ Success = $true; Path = $configPath }
        } catch {
            return @{ Success = $false; Extra = "Could not configure GMRC source: $($_.Exception.Message)" }
        }
    }

# Step 6: Move lua files to config\lua
$null = Show-SpinnerAndResult `
    -SpinnerText 'Move lua files' `
    -Action {
        $sp = $using:steamPath
        $srcDir = Join-Path $sp "config\stplug-in"
        $dstDir = Join-Path $sp "config\lua"

        try {
            if (-not (Test-Path $dstDir)) { $null = New-Item -Path $dstDir -ItemType Directory -Force -ErrorAction Stop }
            if (-not (Test-Path $srcDir)) { return @{ Success = $true; Path = '0 file(s) moved' } }

            $luaFiles = Get-ChildItem -Path $srcDir -Filter "*.lua" -ErrorAction SilentlyContinue
            $moved = 0
            foreach ($f in $luaFiles) {
                Move-Item -Path $f.FullName -Destination (Join-Path $dstDir $f.Name) -Force -ErrorAction Stop
                $moved++
            }
            return @{ Success = $true; Path = "$moved file(s) moved" }
        } catch {
            return @{ Success = $false; Extra = "Could not move lua files: $($_.Exception.Message)" }
        }
    }

# Step 7: Remove legacy SteamProof lines from lua files
$null = Show-SpinnerAndResult `
    -SpinnerText 'Clean lua files' `
    -Action {
        $sp = $using:steamPath
        $pDir = Join-Path $sp "config\lua"
        if (-not (Test-Path $pDir)) { return @{ Success = $true; Path = '' } }

        $luaFiles = Get-ChildItem -Path $pDir -Filter "*.lua" -ErrorAction SilentlyContinue
        $cleaned = 0

        foreach ($f in $luaFiles) {
            $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match "SteamProof") {
                $lines = Get-Content $f.FullName
                $filtered = $lines | Where-Object { $_ -notmatch "^-- SteamProof" -and $_ -notmatch "^setManifestid" }
                while ($filtered.Count -gt 0 -and $filtered[-1].Trim() -eq "") {
                    $filtered = $filtered[0..($filtered.Count - 2)]
                }
                $filtered | Set-Content $f.FullName -Encoding UTF8
                $cleaned++
            }
        }

        return @{ Success = $true; Path = "$cleaned file(s) cleaned" }
    }

# Step 8: Remove UTF-8 BOM from lua files
$null = Show-SpinnerAndResult `
    -SpinnerText 'Fix lua files' `
    -Action {
        $sp = $using:steamPath
        $pDir = Join-Path $sp "config\lua"
        if (-not (Test-Path $pDir)) { return @{ Success = $true; Path = '' } }
        $luaFiles = Get-ChildItem -Path $pDir -Filter "*.lua" -EA SilentlyContinue
        $fixed = 0
        $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
        foreach ($f in $luaFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq $bom[0] -and $bytes[1] -eq $bom[1] -and $bytes[2] -eq $bom[2]) {
                [System.IO.File]::WriteAllBytes($f.FullName, $bytes[3..($bytes.Length - 1)])
                $fixed++
            }
        }
        return @{ Success = $true; Path = "$fixed file(s) fixed" }
    }

Write-Host ''
Write-Host ([char]0x2713) 'Process completed' -BackgroundColor Green -ForegroundColor Black
Write-Host ''
Write-Host 'To add games or apps:' -ForegroundColor Yellow
Write-Host 'Move each downloaded .lua file into this folder:' -ForegroundColor White
Write-Host "  $(Join-Path $steamPath 'config\lua')" -ForegroundColor White
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