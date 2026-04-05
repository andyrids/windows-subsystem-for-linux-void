#!/usr/bin/env pwsh
#requires -RunAsAdministrator
#requires -version 5.1

<#
.SYNOPSIS
    This script bootstraps a Void Linux WSL2 distribution with dotfile configuration.

.DESCRIPTION
    This script downloads the latest version of Void Linux and bootstraps configuration on WSL with
    files from the `.config/` directory.

.PARAMETER InstallDirectory
    WSL distribution install path. Defaults to `%USERPROFILE%\WSL\Void`.

.PARAMETER DistroName
    Optional WSL distribution name. Defaults to `Void-<version>`.

.LINK
    https://github.com/andyrids/windows-subsystem-for-linux-void
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallDirectory,
    [Parameter(Mandatory=$false)]
    [string]$DistroName
)

$Script:ImageImported = $false
$Script:UnicodeSupport = [Console]::OutputEncoding.EncodingName -match "UTF-8" -or $Host.Name -match "Visual Studio Code" -or $PSVersionTable.PSVersion.Major -ge 7

$Script:Theme = @{
    IndentChar  = "  "
    SuccessIcon = if ($UnicodeSupport) { "✔" } else { "[ OK ]" }
    FailIcon    = if ($UnicodeSupport) { "✖" } else { "[FAIL]" }
    WaitSuffix  = "..."
    ColorHeader = "Cyan"
    ColorSuccess= "Green"
    ColorFail   = "Red"
    ColorDim    = "Gray"
}

if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSStyle -and $PSStyle.Progress) {
    $PSStyle.Progress.View = 'Minimal'
}

$Script:AsciiArt = @"
                        ..........
                   .::::::::::::::::::..
               ..:::::::::::::::::::::::::.
                '::::::::::::::::::::::::::::.
                  ':::::''      '':::::::::::::.
`$3         ..         `$1'                '':::::::::.
`$3        .||.                            `$1':::::::::
`$3       .|||||.                            `$1'::::::::
`$3      .|||||||:                             `$1::::::::
`$3      |||||||:          `$1.::::::::.           ::::::::
`$2 ######`$3||||||'   `$2##^ v##########v`$1::. `$2#####  #############v
`$2  ######`$3||||| `$2##^ v####`$1::::::`$2####v`$1::`$2#####  #####`$1:::::`$2#####
`$2   ######`$3||`$2##^   #####`$1::::::`$2#####`$1::`$2#####  #####`$1:::::`$2######
`$2    ######^`$3||    `$2#####`$1:::::`$2####^`$1::`$2#####  #####`$1:::::`$2#####^
`$2     ##^`$3|||||    `$2^###########^`$1:::`$2#####  ##############^
`$3      |||||||:          `$1'::::::::'          .::::::::
`$3      '|||||||:                            `$1.::::::::'
`$3       '|||||||:.                           `$1'::::::
`$3        '||||||||:.                           `$1':::
`$3         ':|||||||||.                .          `$1'
`$3           '|||||||||||:...    ...:||||.
             ':||||||||||||||||||||||||||.
                ':|||||||||||||||||||||||''
                   '':||||||||||||||:''

"@

function Show-Header {
    [CmdletBinding()]
    param()
    process {
        $ESC = [char]27
        $BrightGreen = "$ESC[92m"
        $BrightWhite = "$ESC[97m"
        $NormalGreen = "$ESC[32m"
        $ResetColour = "$ESC[0m"

        $VoidLogo = $Script:AsciiArt.
            Replace('$1', $BrightGreen).
            Replace('$2', $BrightWhite).
            Replace('$3', $NormalGreen) + $ResetColour

        Write-Host $VoidLogo
    }
}


function Get-CursorPosition {
    <#
    .SYNOPSIS
        Gets the current cursor XY position.

    .DESCRIPTION
        Gets the current cursor coordinates as an object with X & Y properties.

    .EXAMPLE
        $CursorPosition = Get-CursorPosition
    #>
    [CmdletBinding()]
    param()

    process {
        [PSCustomObject]@{ X = [Console]::CursorLeft; Y = [Console]::CursorTop }
    }
}


function Reset-CursorPosition {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess("Console Cursor", "Reset to Column 0")) {
        if ($Host.UI.RawUI.CursorPosition) {
            $Coordinates = New-Object System.Management.Automation.Host.Coordinates(
                5, $Host.UI.RawUI.CursorPosition.Y
            )
            $Host.UI.RawUI.CursorPosition = $Coordinates
        } else {
            # Fallback for ISE/VSCode consoles
            Write-Host "`r" -NoNewline
        }
    }
}


function Show-TaskProgress {
    <#
    .SYNOPSIS
        Displays the progress of a task.

    .DESCRIPTION
        Displays the progress of a task with a status indicator.

    .PARAMETER TaskName
        The name of the task.

    .PARAMETER TaskResult
        The result of the task. Valid values are "NONE", "OK", "WARN", "FAIL".

    .PARAMETER ToTitleCase
        A switch indicating whether to convert the task name to title case.

    .EXAMPLE
        Show-TaskProgress -TaskName "Task One" -TaskResult "OK"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position=0, Mandatory)]
        [string]
        $TaskName,
        [Parameter(Position=1, Mandatory)]
        [ValidateSet("NONE", "OK", "WARN", "FAIL")]
        [string]
        $TaskResult,
        [Parameter(Position=2, Mandatory=$false)]
        [switch]
        $ToTitleCase
    )

    $TaskNameDisplay = " $TaskName"

    if ($ToTitleCase) {
        $TextInfo = (Get-Culture).TextInfo
        $TaskNameDisplay = $TextInfo.ToTitleCase($TaskNameDisplay)
    }

    $Status = switch ($TaskResult) {
        "NONE" { @{ Object = "[....]"; ForegroundColor = "Gray" } }
        "OK"   { @{ Object = "[ OK ]"; ForegroundColor = "Green" } }
        "WARN" { @{ Object = "[WARN]"; ForegroundColor = "Yellow" } }
        "FAIL" { @{ Object = "[FAIL]"; ForegroundColor = "Red" } }
    }

    Write-Host " $($Status.Object)" -ForegroundColor $Status.ForegroundColor -NoNewline
    Write-Host "$TaskNameDisplay"
}


function Show-TaskErrorMessage {
    <#
    .SYNOPSIS
        Displays an Exception message raised within a task.

    .DESCRIPTION
        Displays Exception messages raised during task execution in red.

    .PARAMETER ErrorRecord
        An `ErrorRecord` object raised during task execution.

    .EXAMPLE
        Show-TaskErrorMessage -ErrorRecord $_
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [System.Management.Automation.ErrorRecord]
        $ErrorRecord
    )
    Write-Host "`n  - $($ErrorRecord.Exception.Message)`n" -ForegroundColor Red
}


function Invoke-Task {
    <#
    .SYNOPSIS
        Invokes a series of `ScriptBlock` objects as steps of a task.

    .DESCRIPTION
        This PowerShell function is designed to wrap individual components of the WSL distro configuration.

    .PARAMETER Name
        Name of task.

    .PARAMETER Steps
        Series of `ScriptBlock` objects forming steps of the task.

    .PARAMETER Critical
        A switch causing terminal exit on task failure, if set.

    .PARAMETER ToTitleCase
        A switch causing title-case setting for `$Name`, if set.

    .EXAMPLE
        Invoke-Task -Name "Task One" -Steps @({ ... }, { ... })
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory)]
        [string]
        $Name,
        [Parameter(Position=1, Mandatory)]
        [ScriptBlock[]]
        $Steps,
        [Parameter(Position=2, Mandatory=$false)]
        [switch]
        $Critical,
        [Parameter(Position=3, Mandatory=$false)]
        [switch]
        $ToTitleCase
    )

    process {
        $TaskNameDisplay = if ($ToTitleCase) {
            " $((Get-Culture).TextInfo.ToTitleCase($Name))"
        } else {
            " $Name"
        }

        $StepCount = [Math]::Max($Steps.Count, 1)
        $ProgressId = 1

        try {
            for ($StepIndex = 0; $StepIndex -lt $Steps.Count; $StepIndex++) {
                $Percent = [int]((($StepIndex + 1) / $StepCount) * 100)
                Write-Progress -Id $ProgressId -Activity $TaskNameDisplay -Status "Step $($StepIndex + 1) of $StepCount" -PercentComplete $Percent

                & $Steps[$StepIndex]
            }

            Write-Progress -Id $ProgressId -Activity $TaskNameDisplay -Completed
            Show-TaskProgress -TaskName $Name -TaskResult OK -ToTitleCase:$ToTitleCase
            Start-Sleep -Milliseconds 400
        } catch {
            Write-Progress -Id $ProgressId -Activity $TaskNameDisplay -Completed
            $Result = if ($Critical) { "FAIL" } else { "WARN" }
            Show-TaskProgress -TaskName $Name -TaskResult $Result -ToTitleCase:$ToTitleCase
            Show-TaskErrorMessage -ErrorRecord $_

            if ($Critical) {
                Write-Host " [ABORT] CRITICAL TASK`n" -ForegroundColor Red
                if ($ImageImported) {
                    Write-Host "  - Distro imported [not configured] -`n" -ForegroundColor DarkYellow
                    Write-Host "  - ``wsl --list``" -ForegroundColor DarkYellow
                    Write-Host "  - ``wsl --unregister <name>```n" -ForegroundColor DarkYellow
                }
                exit 1
            }
        }
    }
}


function Invoke-TerminateDistribution {
    <#
    .SYNOPSIS
        Terminates a specific WSL Linux distro in a structured manner.

    .DESCRIPTION
        This PowerShell function is designed to safely & cleanly terminate a Void Linux instance.

    .PARAMETER DistroName
        Name of the Linux distribution.

    .EXAMPLE
        Invoke-TerminateDistribution -DistroName "Void-2025.02.02"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0, Mandatory)]
        [string]
        $DistroName
    )

    process {
        Invoke-Task -Name "Terminating $DistroName" -Critical -Steps @(
            {
                # Trigger runit stage 3 to stop any daemons if `runsvdir` is running
                $Command = "if pidof runsvdir > /dev/null 2>&1; then /etc/runit/3; fi"
                $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1
                if ($LASTEXITCODE -ne 0) { Write-Warning "`/etc/runit/3` exit status $LASTEXITCODE" }

                # Force a sync inside Linux first to flush buffers
                wsl.exe -d $DistroName -u root -- /bin/sh -c "sync" | Out-Null

                # Wait for Windows host to finalise I/O operations
                Start-Sleep -Seconds 2

                $Log = wsl.exe --terminate $DistroName 2>&1
                if ($LASTEXITCODE -ne 0) { throw " - Failed to terminate $DistroName - $Log" }
            }
        )
    }
}


function Get-LatestRootfsVersion {
    <#
    .SYNOPSIS
        Resolves the latest Void x86_64 ROOTFS tarball from CDN links.

    .DESCRIPTION
        Parses ROOTFS filenames, validates their YYYYMMDD date token and returns
        the newest version by date.

    .PARAMETER Links
        Collection of links from Invoke-WebRequest response.

    .EXAMPLE
        $VersionInfo = Get-LatestRootfsVersion -Links $Response.Links
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object[]]
        $Links
    )

    process {
        $CandidatePattern = '^void-x86_64-ROOTFS-(\d{8})\.tar\.xz$'

        $Candidates = foreach ($Link in $Links) {
            if (-not $Link.href) { continue }

            $Match = [regex]::Match($Link.href, $CandidatePattern)
            if (-not $Match.Success) { continue }

            $DateToken = $Match.Groups[1].Value
            try {
                $ParsedDate = [DateTime]::ParseExact(
                    $DateToken, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture
                )
            }
            catch {
                continue
            }

            [PSCustomObject]@{
                FileName = $Link.href
                Date     = $ParsedDate
            }
        }

        if (-not $Candidates) {
            throw 'No valid ROOTFS versions were found in CDN response.'
        }

        $Latest = $Candidates |
            Sort-Object -Property Date, FileName |
            Select-Object -Last 1

        [PSCustomObject]@{
            LatestVersion = $Latest.FileName
            VersionString = $Latest.Date.ToString('yyyy.MM.dd')
        }
    }
}


function Invoke-WebRequestWithRetry {
    <#
    .SYNOPSIS
        Invokes Invoke-WebRequest with retry and timeout handling.

    .PARAMETER Uri
        Request URI.

    .PARAMETER OutFile
        Optional output file path for downloads.

    .PARAMETER TimeoutSec
        Per-attempt request timeout in seconds.

    .PARAMETER MaxAttempts
        Maximum number of request attempts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,
        [Parameter(Mandatory = $false)]
        [string]$OutFile,
        [Parameter(Mandatory = $false)]
        [ValidateRange(5, 300)]
        [int]$TimeoutSec = 30,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 6)]
        [int]$MaxAttempts = 3
    )

    process {
        for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
            try {
                $RequestParams = @{
                    Uri             = $Uri
                    UseBasicParsing = $true
                    TimeoutSec      = $TimeoutSec
                    ErrorAction     = "Stop"
                }

                if ($PSBoundParameters.ContainsKey("OutFile")) {
                    $RequestParams["OutFile"] = $OutFile
                }

                return Invoke-WebRequest @RequestParams
            }
            catch {
                if ($Attempt -eq $MaxAttempts) {
                    throw "Request failed for '$Uri' after $MaxAttempts attempts - $($_.Exception.Message)"
                }

                Start-Sleep -Seconds ([Math]::Min($Attempt * 2, 6))
            }
        }
    }
}

# -----------------------------------------------------------------------------
# INITIALISATION
# -----------------------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Resolve `InstallVoidLinux.ps1` location regardless of invocation method
$RootPath = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PWD.Path
}

$DEFAULT_WSL_PATH = Join-Path -Path $env:USERPROFILE -ChildPath "WSL\Void"

Clear-Host
Show-Header

# -----------------------------------------------------------------------------
# VALIDATE INPUT
# -----------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = $DEFAULT_WSL_PATH
}

Invoke-Task -Name "Checking installation PATH" -Critical -Steps @(
    {
        if ($InstallDirectory -match '[\x00-\x1F]') {
            throw 'Install path contains unsupported control characters.'
        }

        $Script:InstallDirectory = [Environment]::ExpandEnvironmentVariables($InstallDirectory)
        $Script:InstallDirectory = $Script:InstallDirectory -replace '"',''
        $Script:InstallDirectory = [System.IO.Path]::GetFullPath($Script:InstallDirectory)

        if (-not (Test-Path -Path $Script:InstallDirectory)) {
            New-Item -ItemType Directory -Path $Script:InstallDirectory -Force | Out-Null
        }

        # Test write access
        $TemporaryFile = Join-Path $Script:InstallDirectory "BOOTSTRAP.tmp"
        New-Item -Path $TemporaryFile -ItemType File -Force | Remove-Item -Force
    }
)

Invoke-Task -Name "Checking prerequisites" -Critical -Steps @(
    {
        $Null = Get-Command -Name tar.exe -ErrorAction Stop
    }
)

# -----------------------------------------------------------------------------
# WSL SERVICE CHECKS
# -----------------------------------------------------------------------------

Invoke-Task -Name "Checking ``WslService`` status" -Critical -Steps @(
    {
        $WSLService = Get-Service -Name WslService -ErrorAction Stop
        if ($WSLService.StartupType -eq 'Disabled') {
            Set-Service -Name WslService -StartupType Automatic -ErrorAction Stop
        }

        if ($WSLService.Status -ne 'Running') {
            Start-Service -Name WslService -ErrorAction Stop
            $WSLService = Get-Service -Name WslService -ErrorAction Stop
            if ($WSLService.Status -ne 'Running') {
                throw 'WslService is not running after start attempt.'
            }
        }
    }
)

Invoke-Task -Name "Checking WSL updates" -Steps @(
    {
        # Suppress output unless error
        $UpdateLog = wsl.exe --update 2>&1
        if ($LASTEXITCODE -ne 0) { throw "WSL update failed - $UpdateLog" }
    }
)

# -----------------------------------------------------------------------------
# DOWNLOAD VOID LINUX MINIROOTFS
# -----------------------------------------------------------------------------

$VOID_CDN = "https://repo-default.voidlinux.org/live/current/"
$LatestVersion = $null
$VersionString = $null

Invoke-Task -Name "Checking Void CDN" -Critical -Steps @(
    {
        $Response = Invoke-WebRequestWithRetry -Uri $VOID_CDN
        if ($Response.StatusCode -ne 200) { throw "$VOID_CDN - HTTP $($Response.StatusCode)" }

        $VersionInfo = Get-LatestRootfsVersion -Links $Response.Links
        $Script:LatestVersion = $VersionInfo.LatestVersion
        $Script:VersionString = $VersionInfo.VersionString

        if (-not $Script:VersionString) { throw "Version parsing error - '$Script:LatestVersion'" }
    }
)


function Test-TarfileHash {
    [CmdletBinding()]
    param(
        [string]$TarFile,
        [string]$CheckSumURL,
        [string]$LatestVersion
    )

    process {
        $Content = (Invoke-WebRequestWithRetry -Uri $CheckSumURL).Content
        if ($Content -is [byte[]]) { $Content = [System.Text.Encoding]::UTF8.GetString($Content) }

        $EscapedVersion = [regex]::Escape($LatestVersion)
        $RemoteHash = $null

        foreach ($Line in ($Content -split "`r?`n")) {
            if ($Line -match "^SHA256\s*\($EscapedVersion\)\s*=\s*([0-9a-fA-F]{64})\s*$") {
                $RemoteHash = $Matches[1].ToLower()
                break
            }

            if ($Line -match "^([0-9a-fA-F]{64})\s+\*?$EscapedVersion\s*$") {
                $RemoteHash = $Matches[1].ToLower()
                break
            }
        }

        if (-not $RemoteHash) {
            throw "Hash line not found or malformed for $LatestVersion"
        }

        $LocalHash  = (Get-FileHash -Path $TarFile -Algorithm SHA256).Hash.ToLower()

        if ($RemoteHash -ne $LocalHash) {
            Remove-Item $TarFile -Force -ErrorAction SilentlyContinue
            throw "SHA256 mismatch for cached $TarFile (expected $RemoteHash, got $LocalHash). File deleted."
        }
    }
}


$DefaultDistroName = "Void-${VersionString}"
$TarFile = Join-Path $RootPath $LatestVersion

Invoke-Task -Name "Resolving distro name" -Critical -Steps @(
    {
        $DistroList = wsl.exe --list --quiet |
            ForEach-Object { ($_ -replace "`0", "").Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        $RequestedName = if ([string]::IsNullOrWhiteSpace($DistroName)) {
            $DefaultDistroName
        } else {
            $DistroName.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($RequestedName)) {
            throw 'Distro name is empty. Provide -DistroName <name>.'
        }

        if ($DistroList -contains $RequestedName) {
            if (-not [string]::IsNullOrWhiteSpace($DistroName)) {
                throw "Distro '$RequestedName' already exists; choose another with -DistroName <name>."
            }

            $SuggestedName = "$DefaultDistroName-test"
            while ($true) {
                $InputName = Read-Host " Enter distro name [$SuggestedName]"
                if ([string]::IsNullOrWhiteSpace($InputName)) {
                    $InputName = $SuggestedName
                }

                $InputName = $InputName.Trim()

                if ([string]::IsNullOrWhiteSpace($InputName)) {
                    continue
                }

                if ($DistroList -contains $InputName) {
                    Write-Host "  - '$InputName' already exists" -ForegroundColor Yellow
                    $SuggestedName = "$InputName-test"
                    continue
                }

                $RequestedName = $InputName
                break
            }
        }

        $Script:DistroName = $RequestedName
    }
)

$DistroName = $Script:DistroName

if (-not (Test-Path $TarFile)) {
    Invoke-Task -Name "Downloading $LatestVersion" -Critical -Steps @(
        {
            Invoke-WebRequestWithRetry -Uri "${VOID_CDN}${LatestVersion}" -OutFile $TarFile | Out-Null
            if (-not (Test-Path -Path $TarFile -PathType Leaf)) {
                throw "Download completed without creating expected tarball: $TarFile"
            }
        }
    )
}

Invoke-Task -Name "Verifying $LatestVersion" -Critical -Steps @(
    { Test-TarfileHash -TarFile $TarFile -CheckSumURL "${VOID_CDN}sha256sum.txt" -LatestVersion $LatestVersion }
)

# -----------------------------------------------------------------------------
# IMPORT VOID LINUX DISTRO
# -----------------------------------------------------------------------------

$ImageDirectory = $null

Invoke-Task -Name "Importing $LatestVersion" -Critical -Steps @(
    {
        # Check existing distributions
        $DistroList = wsl.exe --list --quiet | ForEach-Object { ($_ -replace "`0", "").Trim() }
        if ($DistroList -contains $DistroName) {
            throw "'$DistroName' exists; choose another with -DistroName <name>"
        }

        # All WSL images are named `ext4.vhdx`, so we place them in $InstallDirectory\$DistroName DIR
        $Script:ImageDirectory = New-Item -Path $InstallDirectory -Name $DistroName -ItemType "Directory" |
            Select-Object -ExpandProperty FullName

        $ImportLog = wsl.exe --import $DistroName $ImageDirectory $TarFile 2>&1
        if ($LASTEXITCODE -ne 0) { throw "WSL import failed - $ImportLog" }
        # Allow Windows to finalize the VHDX handle
        Start-Sleep -Seconds 3

        $Script:ImageImported = $true
    }
)

# -----------------------------------------------------------------------------
# UPDATE & UPGRADE PACKAGES
# -----------------------------------------------------------------------------

Invoke-Task -Name "Installing packages" -Critical -Steps @(
    {
        $Packages = @(
            "util-linux",
            "base-devel",
            "fastfetch",
            "git",
            "just",
            "python3",
            "python3-devel",
            "tree",
            "fcron",
            "vim",
            "wget",
            "socklog",
            "socklog-void",
            "dos2unix"
        )
        # Attempt an upgrade of `xbps`
        $Command = "xbps-install -Su --yes xbps"
        wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1 | Out-Null

        # Full system upgrade
        $Command = "xbps-install -Su --yes"
        $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Failed to upgrade base system - $Log" }

        # Install required packages
        $Command = "xbps-install --yes $($Packages -join ' ')"
        $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Failed to install required packages - $Log" }
    },
    {
        # Remove orphaned packages
        $Command = "xbps-remove -Oo --yes"
        $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Failed to remove orphaned packages - $Log" }
    }
)

# -----------------------------------------------------------------------------
# CONFIGURATION BOOTSTRAP
# -----------------------------------------------------------------------------

Invoke-Task -Name "Importing bootstrap files" -Critical -Steps @(
    {
        $DotConfigPath = Join-Path -Path $RootPath -ChildPath ".config"
        if (-not (Test-Path -Path $DotConfigPath -PathType Container)) {
            throw "Missing bootstrap directory - '$DotConfigPath'"
        }

        $Log = wsl.exe -d $DistroName -u root -- /bin/true 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Distro '$DistroName' failed to start - $Log" }

        Push-Location $DotConfigPath
        try {
            $Log = wsl.exe -d $DistroName -u root -- mkdir -p /tmp/bootstrap
            if ($LASTEXITCODE -ne 0) { throw "Failed to create bootstrap staging DIR - $Log" }

            # Windows `tar.exe` compress -> Pipe -> Linux `tar` extraction directly into `/tmp/bootstrap`
            $Log = cmd.exe /c "tar -cf - . | wsl.exe -d $DistroName -u root -- tar -xf - -C /tmp/bootstrap" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to compress & extract boostrap file - $Log" }

            #  Let Linux handle CRLF -> LF conversion (ONLY in `/tmp/bootstrap`)
            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "find /tmp/bootstrap -type f -exec dos2unix --quiet --safe {} +" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to handle CRLF -> LF conversion - $Log" }

            # Copy sanitised files to their correct locations in `/`
            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "cp -a /tmp/bootstrap/. / && rm -rf /tmp/bootstrap" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to copy sanitised bootstrap files - $Log" }

            # Normalize permissions for `/etc/skel` contents
            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "find /etc/skel -type d -exec chmod 755 {} + && find /etc/skel -type f -exec chmod 644 {} +" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to normalize /etc/skel permissions - $Log" }
        }
        finally { Pop-Location }
    }
)

# -----------------------------------------------------------------------------
# CONFIGURE RUNIT SERVICES & RUNLEVELS
# -----------------------------------------------------------------------------

Invoke-Task -Name "Configuring ``runit`` services" -Critical -Steps @(
    {
        <#
        In Void Linux, all available services are stored as directories inside `/etc/sv/`.
        To enable a service (WSL context), create a symbolic link of that service's DIR into
        `/etc/runit/runsvdir/default/` and NOT the typical `/var/service/` DIR.
        #>

        # Remove default `agetty` services baked into the ROOTFS
        $Command = "rm -f /etc/runit/runsvdir/default/agetty-*"
        wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1 | Out-Null

        $Services = @(
            "udevd",        # Device management (passthrough via `usbipd-win`)
            "socklog-unix", # Logging daemon (`/var/log/socklog/`)
            "nanoklogd",    # Kernel logging
            "fcron"         # Cron daemon
        )

        foreach ($Service in $Services) {
            # Target the persistent `/etc/runit/runsvdir/default/` NOT `/var/service/`
            $Command = "if [ ! -d /etc/sv/$Service ]; then echo 'missing required service: $Service' >&2; exit 1; fi; ln -sfn /etc/sv/$Service /etc/runit/runsvdir/default/$Service"
            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to configure runit service '$Service' - $Log" }

            $Command = "test -L /etc/runit/runsvdir/default/$Service"
            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Service symlink missing after configuration for '$Service' - $Log" }
        }
    },
    {
        <#
        Apply strict log rotation limits to `svlogd` through a `config` file (1MB max, keep 2 files)
        inside EVERY `socklog` subdirectory.
        #>
        $Command = 'if [ ! -d /var/log/socklog ]; then echo "Missing /var/log/socklog directory" >&2; exit 1; fi; HasDirs=0; for dir in /var/log/socklog/*; do if [ -d "$dir" ]; then HasDirs=1; printf "s1048576\nn2" > "$dir/config"; fi; done; if [ "$HasDirs" -eq 0 ]; then echo "No socklog output directories found under /var/log/socklog" >&2; exit 1; fi'

        $Log = wsl.exe -d $DistroName -u root -- /bin/bash -c "$Command" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Failed to apply `socklog` policies - $Log" }
    }
)

# -----------------------------------------------------------------------------
# CONFIGURE WINDOWS GIT INTEROP
# -----------------------------------------------------------------------------

Invoke-Task -Name "Configuring ``Git`` settings" -Steps @(
    {
        try {
            $GitCmdPath = (Get-Command git -ErrorAction Stop).Source
        }
        catch { throw "Git is not installed - ``winget install --id Git.Git -e --source winget``" }

        <#
        On Windows, Git usually sets `credential.helper` to 'manager' which resolves to 'credential-manager' and
        relates to the Git Credential Manager (GCM) that ships with Git.

        As an example, `git.exe` is typically @ `C:\Program Files\Git\cmd` and GCM would therefore be
        found at `C:\Program Files\Git\mingw64\bin\`.
        #>

        $Log = git credential-manager --version
        if ($LASTEXITCODE -ne 0) { throw "Git Credential Manager is not installed - $Log" }

        $GitBasePath = $GitCmdPath | Split-Path -Parent | Split-Path -Parent
        $GCMPath = Join-Path -Path $GitBasePath -ChildPath "mingw64\bin\git-credential-manager.exe"

        # Update skeleton config for all users
        $ConfigFile = "/etc/skel/.config/git/config"

        if (Test-Path -Path $GCMPath -PathType Leaf) {
            # $GCMLinuxPath = wsl.exe -d $DistroName wslpath -u "$GCMPath"
            # $GCMLinuxPath = wsl.exe -d $DistroName /bin/bash -c "printf '%q' '$GCMLinuxPath'"
            $GCMLinuxPath = wsl.exe -d $DistroName /bin/bash -c "printf '%q' `"`$(wslpath -u '$GCMPath')`""

            $Log = wsl.exe -d $DistroName git config set -f "$ConfigFile" credential.helper "$GCMLinuxPath"
            if ($LASTEXITCODE -ne 0) { throw "Error setting Git credential.helper - $Log" }
        } else { throw "Git Credential Manager not found @ '$GCMPath'" }

        $GitUserName = git config get user.name
        $GitUserEmail = git config get user.email

        if  (-not ($GitUserName -and $GitUserEmail)) {
            throw "user.name & user.email are unset in Windows Git config"
        }

        $Log = wsl.exe -d $DistroName git config set -f "$ConfigFile" user.name "$GitUserName"
        if ($LASTEXITCODE -ne 0) { throw "Error setting Git user.name - $Log" }

        $Log = wsl.exe -d $DistroName git config set -f "$ConfigFile" user.email "$GitUserEmail"
        if ($LASTEXITCODE -ne 0) { throw "Error setting Git user.email - $Log" }
    }
)

# -----------------------------------------------------------------------------
# CREATING DEFAULT USER
# -----------------------------------------------------------------------------

Invoke-Task -Name "Creating default ``void`` user " -Critical -Steps @(
    {
        <#
        Create a default user `void` with a home directory, `bash` default login shell
        and wheel, dialout & socklog group membership.
        #>
        $Groups = @("wheel", "dialout", "socklog")
        $Command = "id void >/dev/null 2>&1 || useradd -m -s /bin/bash void && usermod -aG $($Groups -join ',') void"
        $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command"

        if ($LASTEXITCODE -ne 0) { throw "Failed to create default user - $Log" }
    },
    {
        <#
        Grant passwordless sudo to the wheel group with `/etc/sudoers.d/wheel` instead of modifying
        the `/etc/sudoers` with `sed`.
        #>
        $Command = "echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel && chmod 0440 /etc/sudoers.d/wheel"
        $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command"
        if ($LASTEXITCODE -ne 0) { throw "Failed to grant passwordless sudo to the wheel group - $Log" }

        # Validate syntax before committing
        $Command = "visudo -cf /etc/sudoers.d/wheel || { rm -f /etc/sudoers.d/wheel; exit 1; }"
        $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command"
        if ($LASTEXITCODE -ne 0) { throw "Failed to validate ``/etc/sudoers.d/wheel`` - $Log" }
    }
)

# -----------------------------------------------------------------------------
# TERMINATE DISTRO
# -----------------------------------------------------------------------------

Invoke-TerminateDistribution -DistroName $DistroName

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------

Invoke-Task -Name "- COMPLETE - ``wsl -d $DistroName``" -Steps @({})
Write-Host "`n"
