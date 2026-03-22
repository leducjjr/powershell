# update_server_and_start_it.ps1

A PowerShell script that updates and launches a **Palworld Dedicated Server** on Windows. It pulls the latest server files via SteamCMD, validates the environment, and starts the server process — logging everything to both the console and a timestamped log file for easy triage.

---

## Requirements

- Windows XP or later (including Windows 10/11 and Windows Server)
- PowerShell 5.1 or later
- [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) installed
- Palworld Dedicated Server files (installed by SteamCMD on first run)
- Administrator privileges (recommended)

---

## Configuration

Open the script and edit the four variables near the top:

| Variable | Default | Description |
|---|---|---|
| `$STEAMCMD_PATH` | `C:\steamcmd\steamcmd.exe` | Full path to your SteamCMD executable |
| `$SERVER_PATH` | `C:\palworldserver` | Directory where Palworld server files are installed |
| `$PALWORLD_SERVER_NAME` | `yourservernamehere` | Name shown in the server browser |
| `$PALWORLD_PORT` | `8211` | UDP port the server listens on |

---

## Usage

Right-click the script and choose **Run with PowerShell**, or launch it from an elevated PowerShell prompt:

```powershell
.\update_server_and_start_it.ps1
```

> **Tip:** Run as Administrator to avoid permission issues with `Start-Process` and port binding.

---

## What It Does

The script runs through seven stages in order:

### 1. System Information
Captures a snapshot of the host environment at the time of launch:
- Hostname, OS version, and CPU architecture
- Current user and whether the script is running as Administrator
- PowerShell version
- Total and free RAM
- CPU model and core count

### 2. Configuration Echo
Logs the four configuration values (paths, server name, port) so you can confirm the script is using the settings you expect.

### 3. Path & File Validation
Checks everything needed before attempting a launch:
- **SteamCMD** — verifies the exe exists and logs its size and last-modified date
- **Server directory** — verifies it exists and logs total size and file count
- **PalServer.exe** — verifies it exists at `$SERVER_PATH\PalServer.exe`; if missing, automatically searches common subdirectory locations (e.g. `Pal\Binaries\Win64\`) and suggests alternatives
- **Disk space** — logs free space on the server drive; warns if below 5 GB
- **Port availability** — warns if the configured port is already in use by another process and reports the owning PID

### 4. SteamCMD Update
Runs SteamCMD with `app_update 2394010 validate` to check for and apply any Palworld server updates. Logs the full command, exit code, and how long the update took. The script exits with an error if SteamCMD fails.

### 5. Server Launch
Launches `PalServer.exe` with the following arguments:

| Argument | Value |
|---|---|
| `-ServerName` | Value of `$PALWORLD_SERVER_NAME` |
| `-port` | Value of `$PALWORLD_PORT` |
| `-players` | `32` |
| `-log` | Enables server-side logging |
| `-useperfthreads` | Performance threading optimization |
| `-NoAsyncLoadingThread` | Disables async loading thread |
| `-UseMultithreadForDS` | Enables multithreading for dedicated server |
| `EpicApp=PalServer` | Required Epic/Steam identity flag |
| `-publiclobby` | Makes the server visible in the public lobby |

After launch, the script waits 3 seconds and checks whether the process has already exited — catching immediate crash-on-start scenarios before declaring success.

Once running, the script keeps the window open and waits for input. Pressing **Enter** will shut down the server and exit cleanly.

### 6. Network Information
Runs twice — once before the SteamCMD update (Pre-Launch) and once after the server starts (Post-Launch). Each run logs:

- **Internal address** — all non-loopback IPv4 addresses on the machine combined with the configured port (e.g. `192.168.1.50:8211`). Multiple addresses are logged if the machine has more than one network adapter.
- **External address** — your public IP resolved via `api.ipify.org`, combined with the configured port (e.g. `203.0.113.42:8211`). This is the address remote players use to connect.


### Server Shutdown
When Enter is pressed, the script uses `taskkill /F /T` to force-terminate `PalServer.exe` and its entire process tree. This is necessary because PalServer spawns child processes on startup — killing only the parent would leave the actual server still running in the background. `taskkill /F /T` is compatible with Windows XP and later.

---

## Log Files

Every run produces a timestamped log file in `$SERVER_PATH` named after the script itself:

```
C:\palworldserver\update_server_and_start_it_20260321_143012.log
```

The log file mirrors everything printed to the console and is useful for post-mortem triage when the script window has already closed. Log entries follow this format:

```
[2026-03-21 14:30:12] [INFO]  PalServer.exe launched successfully (PID: 4821)
[2026-03-21 14:30:09] [WARN]  Port 8211 is ALREADY IN USE (PID: 3344)
[2026-03-21 14:30:08] [ERROR] PalServer.exe NOT FOUND at: C:\palworldserver\PalServer.exe
```

Log levels used:

| Level | Meaning |
|---|---|
| `INFO` | Normal progress and status |
| `DEBUG` | Detailed values (paths, arguments, resolved locations) |
| `WARN` | Non-fatal issues worth investigating |
| `ERROR` / `FATAL` | Failures that halt the script |

---

## Common Errors & Fixes

**`The system cannot find the file specified` on Start-Process**
`PalServer.exe` was not found at `$SERVER_PATH`. Check the log for the `Path & File Validation` section — the script will report whether it found the exe elsewhere (e.g. in `Pal\Binaries\Win64\`) and what path to use instead.

**`SteamCMD failed to update the server`**
SteamCMD returned a non-zero exit code. Common causes: no internet connection, firewall blocking Steam, or a corrupted SteamCMD install. Try running SteamCMD manually to see its output.

**`Port 8211 is ALREADY IN USE`**
Another process (possibly a previous server instance) is holding the port. Use `Stop-Process -Id <PID>` to terminate it, or change `$PALWORLD_PORT` in the script.

**Script exits immediately without launching**
Ensure you are running as Administrator. Some systems restrict `Start-Process` for non-admin users.

# Example screenshots

<img width="1519" height="628" alt="image" src="https://github.com/user-attachments/assets/678c9aff-b319-4e28-9ac1-93f28e86ce5d" />

<img width="1519" height="628" alt="image" src="https://github.com/user-attachments/assets/4326abb2-30e1-4474-8a9c-b1564110a939" />

<img width="1519" height="628" alt="image" src="https://github.com/user-attachments/assets/0118083e-8688-4a80-9b0b-18867c59e9da" />

<img width="1519" height="628" alt="image" src="https://github.com/user-attachments/assets/336a81c8-976c-4515-b319-72f358ed5ef8" />
