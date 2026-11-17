<#
.SYNOPSIS
    Push android/ and debian/ to a rooted Android device over ADB and mirror
    them into place via scripts/install-on-device.sh.

.DESCRIPTION
    Windows host wrapper for deploying or updating the appliance scripts over
    USB ADB or TCP ADB. Stages android/, debian/, and scripts/install-on-device.sh
    into /data/local/tmp on the device (since adbd runs as the unprivileged
    `shell` user), executes install-on-device.sh as root via `su`, and removes
    both local and remote staging directories afterward.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER Serial
    ADB device serial (USB serial or HOST:PORT). Alias: -s.

.PARAMETER Target
    TCP ADB host or HOST:PORT to connect to first (defaults to port 5555).
    Alias: -t.

.PARAMETER Adb
    Path to the adb executable. Defaults to `adb` on PATH.

.PARAMETER DebianRoot
    Destination Debian chroot directory on Android.
    Defaults to `/data/local/chroot-distro/debian-trixie`.

.PARAMETER DryRun
    Preview destination paths and file modes without modifying files on the
    device.

.PARAMETER Help
    Display this usage summary and exit. Alias: -h.

.EXAMPLE
    .\scripts\deploy.ps1 -DryRun
    Preview all mirrored files and modes on the connected USB device.

.EXAMPLE
    .\scripts\deploy.ps1 -Target 192.168.1.50
    Connect to 192.168.1.50:5555 over TCP ADB and install/update files.

.EXAMPLE
    .\scripts\deploy.ps1 -Serial ABC123456 -DebianRoot /data/local/chroot-distro/debian-trixie
    Deploy to a specific USB device with an explicit Debian rootfs path.

.NOTES
    Requires an authorized ADB connection and Magisk root (`su`) on the device.
    Ensure the repository is checked out with LF line endings (.gitattributes).
#>
[CmdletBinding()]
param(
    [Alias('s')]
    [string]$Serial,

    [Alias('t')]
    [string]$Target,

    [string]$Adb = 'adb',

    [string]$DebianRoot = '/data/local/chroot-distro/debian-trixie',

    [switch]$DryRun,

    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: deploy.ps1 [options]
  -Serial, -s <serial>         ADB device serial (USB serial or HOST:PORT)
  -Target, -t <host[:port]>    Connect via TCP ADB first (default port: 5555)
  -Adb <path>                  Path to adb executable (default: adb)
  -DebianRoot <path>           Debian rootfs path (default: /data/local/chroot-distro/debian-trixie)
  -DryRun                      Print files and permissions without modifying the device
  -Help, -h                    Show this help
'@
}

if ($Help) {
    Show-Usage
    exit 0
}

# Validate before embedding into the remote `su -c` shell command.
if ($DebianRoot -notmatch '^[A-Za-z0-9._:/-]+$') {
    throw "Invalid characters in -DebianRoot: $DebianRoot"
}

if (-not (Get-Command $Adb -ErrorAction SilentlyContinue)) {
    throw "adb executable not found: $Adb. Pass -Adb <path> or add Android Platform Tools to PATH."
}

# Windows PowerShell 5.1 turns native stderr output into terminating errors when
# $ErrorActionPreference is 'Stop' and 2>$null is used; suppress temporarily for probes.
function Invoke-AdbQuiet {
    param([string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Serial) {
            & $Adb -s $Serial @Arguments 2>$null
        } else {
            & $Adb @Arguments 2>$null
        }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Invoke-Adb {
    param([string[]]$Arguments)
    if ($Serial) {
        & $Adb -s $Serial @Arguments
    } else {
        & $Adb @Arguments
    }
}

if ($Target) {
    if ($Target -notmatch ':') {
        $Target = "${Target}:5555"
    }
    & $Adb connect $Target
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to connect to $Target"
    }
    $Serial = $Target
}

$state = (Invoke-AdbQuiet -Arguments @('get-state') | Out-String).Trim()
if ($state -ne 'device') {
    Write-Error "ADB device not ready (state: $state). Pass -Serial or -Target."
    & $Adb devices -l
    exit 1
}

$suId = (Invoke-AdbQuiet -Arguments @('shell', 'su -c id') | Out-String).Trim()
if ($suId -notmatch 'uid=0\(root\)') {
    throw "Root access via 'su' failed (got: $suId). Check Magisk authorization."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$localStage = Join-Path ([System.IO.Path]::GetTempPath()) ("appliance-deploy-" + [System.Guid]::NewGuid().ToString('N'))
$remoteStage = "/data/local/tmp/appliance-deploy-$PID"

try {
    New-Item -ItemType Directory -Path $localStage | Out-Null
    Copy-Item -Path (Join-Path $repoRoot 'android') -Destination (Join-Path $localStage 'android') -Recurse
    Copy-Item -Path (Join-Path $repoRoot 'debian') -Destination (Join-Path $localStage 'debian') -Recurse
    Copy-Item -Path (Join-Path $scriptDir 'install-on-device.sh') -Destination (Join-Path $localStage 'install-on-device.sh')

    $null = Invoke-AdbQuiet -Arguments @('push', $localStage, $remoteStage)
    if ($LASTEXITCODE -ne 0) {
        throw 'adb push failed'
    }

    $installArgs = New-Object System.Collections.Generic.List[string]
    $installArgs.Add('--debian-root'); $installArgs.Add("'$DebianRoot'")
    if ($DryRun) { $installArgs.Add('--dry-run') }

    $argString = ($installArgs -join ' ')
    $remoteCmd = "sh '$remoteStage/install-on-device.sh' $argString"
    Invoke-Adb -Arguments @('shell', "su -c `"$remoteCmd`"")
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
finally {
    if (Test-Path $localStage) {
        Remove-Item -Path $localStage -Recurse -Force -ErrorAction SilentlyContinue
    }
    try {
        $null = Invoke-AdbQuiet -Arguments @('shell', "rm -rf '$remoteStage'")
    } catch {
    }
}
