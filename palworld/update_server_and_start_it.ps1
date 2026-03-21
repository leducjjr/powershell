if ([Environment]::UserInteractive) { cls }
# Starting Palworld Dedicated Server Update and Launch...

# Set paths for SteamCMD and server installation - EDIT THE PATHS ACCORDINGLY
$STEAMCMD_PATH = "C:\steamcmd\steamcmd.exe"
$SERVER_PATH   = "C:\palworldserver"
$PALWORLD_SERVER_NAME = "yourservernamehere"
$PALWORLD_PORT        = 8211

# Log file path - named after this script with a timestamp
$SCRIPT_BASENAME = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path)
$LOG_FILE = Join-Path $SERVER_PATH "${SCRIPT_BASENAME}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Detect whether the script is running interactively or as a scheduled task / service
$IS_INTERACTIVE = [Environment]::UserInteractive -and [Console]::In.Peek() -ne -1

# -----------------------------------------------------------------------
# Logging helper - writes to console and log file simultaneously
# -----------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",   # INFO | WARN | ERROR | DEBUG | SECTION
        [System.ConsoleColor]$Color = [System.ConsoleColor]::White
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($Level -eq "SECTION") {
        $line = "=" * 60
        $formatted = "`n$line`n  $Message`n$line"
        Write-Host $formatted -ForegroundColor Cyan
        Add-Content -Path $LOG_FILE -Value $formatted
    } else {
        $formatted = "[$timestamp] [$Level] $Message"
        Write-Host $formatted -ForegroundColor $Color
        Add-Content -Path $LOG_FILE -Value $formatted
    }
}

# -----------------------------------------------------------------------
# Helper to write error, log it, and exit
# -----------------------------------------------------------------------
function Throw-ErrorAndExit {
    param([string]$Message, [int]$ExitCode = 1)
    Write-Log "FATAL: $Message" -Level "ERROR" -Color Red
    Write-Log "Script exiting with code $ExitCode" -Level "ERROR" -Color Red
    Write-Host
    Read-Host "Press Enter to exit"
    exit $ExitCode
}

# -----------------------------------------------------------------------
# Network information helper - logs internal/external IPs and port reachability
# -----------------------------------------------------------------------
function Write-NetworkInfo {
    param([string]$Label = "")

    if ($Label) {
        Write-Log "NETWORK INFORMATION ($Label)" -Level "SECTION"
    } else {
        Write-Log "NETWORK INFORMATION" -Level "SECTION"
    }

    # Internal IP addresses (exclude loopback)
    $internalIPs = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
        Select-Object -ExpandProperty IPAddress

    if ($internalIPs) {
        foreach ($ip in $internalIPs) {
            Write-Log "Internal address     : ${ip}:$PALWORLD_PORT" -Level "INFO"
        }
    } else {
        Write-Log "Internal IP          : Could not determine" -Level "WARN" -Color Yellow
    }

    # External/public IP address
    Write-Log "Resolving external IP..." -Level "INFO"
    try {
        $externalIP = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
        Write-Log "External address     : ${externalIP}:$PALWORLD_PORT" -Level "INFO" -Color Green
    } catch {
        Write-Log "External IP          : Could not resolve - check internet connection ($_)" -Level "WARN" -Color Yellow
        $externalIP = $null
    }

    # Check if the port is reachable from the internet
    if ($externalIP) {
        Write-Log "Checking external port reachability..." -Level "INFO"
        try {
            $portCheck = Invoke-RestMethod -Uri "https://api.canyouseeme.org/?port=$PALWORLD_PORT&action=Check" -TimeoutSec 15 -ErrorAction Stop
            if ($portCheck -match "Success") {
                Write-Log "External port $PALWORLD_PORT : REACHABLE from the internet" -Level "INFO" -Color Green
            } else {
                Write-Log "External port $PALWORLD_PORT : NOT REACHABLE - check firewall and router port forwarding" -Level "WARN" -Color Yellow
            }
        } catch {
            # Fallback: try portchecker.co API
            try {
                $portCheck2 = Invoke-RestMethod -Uri "https://portchecker.co/api/v1/query" -Method Post `
                    -ContentType "application/json" `
                    -Body "{`"host`":`"$externalIP`",`"ports`":[$PALWORLD_PORT]}" `
                    -TimeoutSec 15 -ErrorAction Stop
                $portResult = $portCheck2.check | Where-Object { $_.port -eq $PALWORLD_PORT }
                if ($portResult -and $portResult.status -eq $true) {
                    Write-Log "External port $PALWORLD_PORT : REACHABLE from the internet" -Level "INFO" -Color Green
                } else {
                    Write-Log "External port $PALWORLD_PORT : NOT REACHABLE - check firewall and router port forwarding" -Level "WARN" -Color Yellow
                }
            } catch {
                Write-Log "External port $PALWORLD_PORT : Reachability check failed ($_)" -Level "WARN" -Color Yellow
                Write-Log "Manually verify port forwarding for UDP $PALWORLD_PORT on your router" -Level "WARN" -Color Yellow
            }
        }
    }
}

# -----------------------------------------------------------------------
# Create log file and write header
# -----------------------------------------------------------------------
New-Item -ItemType File -Path $LOG_FILE -Force | Out-Null
Write-Log "PALWORLD SERVER LAUNCH TRIAGE LOG" -Level "SECTION"
Write-Log "Log file: $LOG_FILE" -Level "INFO" -Color Cyan

# -----------------------------------------------------------------------
# SECTION 1: System Information
# -----------------------------------------------------------------------
Write-Log "SYSTEM INFORMATION" -Level "SECTION"

$os = Get-CimInstance Win32_OperatingSystem
Write-Log "Hostname         : $($env:COMPUTERNAME)" -Level "INFO"
Write-Log "OS               : $($os.Caption) $($os.Version)" -Level "INFO"
Write-Log "Architecture     : $($env:PROCESSOR_ARCHITECTURE)" -Level "INFO"
Write-Log "Current User     : $($env:USERNAME)" -Level "INFO"
Write-Log "Is Admin         : $((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))" -Level "INFO"
Write-Log "PowerShell Ver   : $($PSVersionTable.PSVersion)" -Level "INFO"
Write-Log "Script Start Time: $(Get-Date)" -Level "INFO"

$ram = Get-CimInstance Win32_OperatingSystem
$totalRamGB = [math]::Round($ram.TotalVisibleMemorySize / 1MB, 2)
$freeRamGB  = [math]::Round($ram.FreePhysicalMemory / 1MB, 2)
Write-Log "Total RAM        : ${totalRamGB} GB" -Level "INFO"
Write-Log "Free RAM         : ${freeRamGB} GB" -Level "INFO"

$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Write-Log "CPU              : $($cpu.Name)" -Level "INFO"
Write-Log "CPU Cores        : $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) logical" -Level "INFO"

# -----------------------------------------------------------------------
# SECTION 2: Configuration
# -----------------------------------------------------------------------
Write-Log "SCRIPT CONFIGURATION" -Level "SECTION"
Write-Log "STEAMCMD_PATH        : $STEAMCMD_PATH" -Level "INFO"
Write-Log "SERVER_PATH          : $SERVER_PATH" -Level "INFO"
Write-Log "PALWORLD_SERVER_NAME : $PALWORLD_SERVER_NAME" -Level "INFO"
Write-Log "PALWORLD_PORT        : $PALWORLD_PORT" -Level "INFO"

# -----------------------------------------------------------------------
# SECTION 3: Network Information (Pre-Launch)
# -----------------------------------------------------------------------
Write-NetworkInfo -Label "Pre-Launch"

# -----------------------------------------------------------------------
# SECTION 4: Path / File Validation
# -----------------------------------------------------------------------
Write-Log "PATH AND FILE VALIDATION" -Level "SECTION"

# SteamCMD
if (Test-Path -Path $STEAMCMD_PATH -PathType Leaf) {
    $steamInfo = Get-Item $STEAMCMD_PATH
    Write-Log "SteamCMD found     : $STEAMCMD_PATH" -Level "INFO" -Color Green
    Write-Log "SteamCMD size      : $([math]::Round($steamInfo.Length / 1KB, 1)) KB" -Level "INFO"
    Write-Log "SteamCMD modified  : $($steamInfo.LastWriteTime)" -Level "INFO"
} else {
    Write-Log "SteamCMD NOT FOUND : $STEAMCMD_PATH" -Level "ERROR" -Color Red
    Throw-ErrorAndExit "steamcmd.exe not found at $STEAMCMD_PATH. Please verify the path."
}

# Server directory
if (Test-Path -Path $SERVER_PATH -PathType Container) {
    Write-Log "Server dir found   : $SERVER_PATH" -Level "INFO" -Color Green
    $dirInfo = Get-ChildItem $SERVER_PATH -Recurse -ErrorAction SilentlyContinue
    $dirSizeGB = [math]::Round(($dirInfo | Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    Write-Log "Server dir size    : ${dirSizeGB} GB ($($dirInfo.Count) files)" -Level "INFO"
} else {
    Write-Log "Server dir MISSING : $SERVER_PATH" -Level "ERROR" -Color Red
    Throw-ErrorAndExit "Server directory not found at $SERVER_PATH. Please verify the path."
}

# PalServer.exe
$serverExe = Join-Path $SERVER_PATH "PalServer.exe"
if (Test-Path -Path $serverExe -PathType Leaf) {
    $exeInfo = Get-Item $serverExe
    Write-Log "PalServer.exe found   : $serverExe" -Level "INFO" -Color Green
    Write-Log "PalServer.exe size    : $([math]::Round($exeInfo.Length / 1MB, 2)) MB" -Level "INFO"
    Write-Log "PalServer.exe modified: $($exeInfo.LastWriteTime)" -Level "INFO"
} else {
    Write-Log "PalServer.exe NOT FOUND at: $serverExe" -Level "WARN" -Color Yellow
    # Search common subdirectory locations
    $candidates = @(
        "Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe",
        "Pal\Binaries\Win64\PalServer.exe",
        "Pal\Binaries\Win64\PalServer-Win64-Shipping.exe"
    )
    $found = $false
    foreach ($candidate in $candidates) {
        $candidatePath = Join-Path $SERVER_PATH $candidate
        if (Test-Path $candidatePath) {
            Write-Log "Alternative exe found: $candidatePath" -Level "WARN" -Color Yellow
            Write-Log "ACTION NEEDED: Update serverExe in script to use this path" -Level "WARN" -Color Yellow
            $found = $true
        }
    }
    if (-not $found) {
        Write-Log "No PalServer executable found anywhere under $SERVER_PATH" -Level "ERROR" -Color Red
        Write-Log "SteamCMD may not have completed installation" -Level "ERROR" -Color Red
    }
}

# Disk space
$drive = Split-Path -Qualifier $SERVER_PATH
$disk = Get-PSDrive ($drive.TrimEnd(':'))
$freeGB = [math]::Round($disk.Free / 1GB, 2)
Write-Log "Free disk on ${drive} : ${freeGB} GB" -Level $(if ($freeGB -lt 5) { "WARN" } else { "INFO" }) -Color $(if ($freeGB -lt 5) { "Yellow" } else { "White" })

# Port availability
$portInUse = Get-NetTCPConnection -LocalPort $PALWORLD_PORT -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Log "Port $PALWORLD_PORT is ALREADY IN USE (PID: $($portInUse.OwningProcess))" -Level "WARN" -Color Yellow
} else {
    Write-Log "Port $PALWORLD_PORT is available" -Level "INFO" -Color Green
}

# -----------------------------------------------------------------------
# SECTION 5: SteamCMD Update
# -----------------------------------------------------------------------
Write-Log "STEAMCMD UPDATE" -Level "SECTION"

$steamCmdArgs = @(
    "+login", "anonymous",
    "+force_install_dir", "`"$SERVER_PATH`"",
    "+app_update", "2394010", "validate",
    "+quit"
)

Write-Log "SteamCMD command: $STEAMCMD_PATH $($steamCmdArgs -join ' ')" -Level "DEBUG" -Color Gray
Write-Log "Running SteamCMD update..." -Level "INFO"

$steamStart = Get-Date
$proc = Start-Process -FilePath $STEAMCMD_PATH -ArgumentList $steamCmdArgs -NoNewWindow -Wait -PassThru
$steamDuration = [math]::Round(((Get-Date) - $steamStart).TotalSeconds, 1)

Write-Log "SteamCMD exit code : $($proc.ExitCode)" -Level $(if ($proc.ExitCode -eq 0) { "INFO" } else { "ERROR" }) -Color $(if ($proc.ExitCode -eq 0) { "Green" } else { "Red" })
Write-Log "SteamCMD duration  : ${steamDuration}s" -Level "INFO"

if ($proc.ExitCode -ne 0) {
    Throw-ErrorAndExit "SteamCMD failed (exit code $($proc.ExitCode)). Check your internet connection or SteamCMD path."
}

# -----------------------------------------------------------------------
# SECTION 6: Server Launch
# -----------------------------------------------------------------------
Write-Log "SERVER LAUNCH" -Level "SECTION"

Set-Location -Path $SERVER_PATH

$serverArgs = @(
    "-ServerName=`"$PALWORLD_SERVER_NAME`"",
    "-port=$PALWORLD_PORT",
    "-players=32",
    "-log",
    "-useperfthreads",
    "-NoAsyncLoadingThread",
    "-UseMultithreadForDS",
    "EpicApp=PalServer",
    "-publiclobby"
)

Write-Log "Executable  : $serverExe" -Level "DEBUG" -Color Gray
Write-Log "Arguments   : $($serverArgs -join ' ')" -Level "DEBUG" -Color Gray
Write-Log "File exists : $(Test-Path $serverExe)" -Level "DEBUG" -Color Gray
Write-Log "Resolved    : $(Resolve-Path $serverExe -ErrorAction SilentlyContinue)" -Level "DEBUG" -Color Gray
Write-Log "Working dir : $(Get-Location)" -Level "DEBUG" -Color Gray

# -----------------------------------------------------------------------
# Cleanup helper - stops the server process by PID
# -----------------------------------------------------------------------
function Stop-ServerProcess {
    param([int]$ProcessId)
    try {
        # Verify the process is still running before attempting to stop it
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        Write-Log "Stopping PalServer.exe and child processes (PID: $ProcessId)..." -Level "INFO" -Color Yellow

        # Use taskkill /F /T to force-kill the entire process tree (PalServer spawns children)
        $result = taskkill /F /T /PID $ProcessId 2>&1
        Write-Log "taskkill: $result" -Level "INFO"

        # Wait up to 10 seconds for the main process to fully exit
        $proc.WaitForExit(10000) | Out-Null

        if ($proc.HasExited) {
            Write-Log "PalServer.exe and child processes stopped successfully." -Level "INFO" -Color Green
        } else {
            Write-Log "PalServer.exe did not exit within 10 seconds after taskkill." -Level "WARN" -Color Yellow
        }
    } catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        Write-Log "PalServer.exe (PID: $ProcessId) is no longer running - no cleanup needed." -Level "INFO"
    } catch {
        Write-Log "Failed to stop PalServer.exe: $_" -Level "WARN" -Color Yellow
    }
}

Write-Log "Launching PalServer.exe..." -Level "INFO"
$serverProc = Start-Process -FilePath $serverExe -ArgumentList $serverArgs -NoNewWindow -PassThru

if ($null -eq $serverProc) {
    Throw-ErrorAndExit "Start-Process returned null - PalServer.exe could not be launched."
}

Start-Sleep -Seconds 3  # Brief pause to let process fail fast if it is going to

if ($serverProc.HasExited) {
    Write-Log "Process exited immediately with code: $($serverProc.ExitCode)" -Level "ERROR" -Color Red
    Throw-ErrorAndExit "PalServer.exe terminated immediately after launch (exit code $($serverProc.ExitCode))."
}

$serverPid = $serverProc.Id
Write-Log "PalServer.exe launched successfully (PID: $serverPid)" -Level "INFO" -Color Green

# -----------------------------------------------------------------------
# SECTION 7: Network Information (Post-Launch)
# -----------------------------------------------------------------------
Write-NetworkInfo -Label "Post-Launch"

Write-Log "Log saved to: $LOG_FILE" -Level "INFO" -Color Cyan

if ($IS_INTERACTIVE) {
    # -----------------------------------------------------------------------
    # Interactive mode - wait for user to press Enter then stop the server
    # -----------------------------------------------------------------------
    Write-Host
    Write-Host "Server started successfully! Press Enter to stop the server and exit." -ForegroundColor Green
    Read-Host
    Write-Log "User requested shutdown." -Level "INFO" -Color Yellow
    Stop-ServerProcess -ProcessId $serverPid
} else {
    # -----------------------------------------------------------------------
    # Non-interactive mode (Task Scheduler / service) - monitor the server
    # process and exit when it stops on its own
    # -----------------------------------------------------------------------
    Write-Log "Running in non-interactive mode - monitoring server process..." -Level "INFO"
    while ($true) {
        Start-Sleep -Seconds 30
        $running = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
        if ($null -eq $running -or $running.HasExited) {
            Write-Log "PalServer.exe (PID: $serverPid) is no longer running - script exiting." -Level "WARN" -Color Yellow
            break
        }
    }
}
