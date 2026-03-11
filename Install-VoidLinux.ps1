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

.LINK
    https://github.com/andyrids/windows-subsystem-for-linux-void
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$InstallDirectory
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

    $Indent = " "

    $Status = switch ($TaskResult) {
        "NONE" { @{ Object = "[....]"; ForegroundColor = "Gray";   NoNewline = $true } }
        "OK"   { @{ Object = "[ OK ]"; ForegroundColor = "Green";  NoNewline = $true } }
        "WARN" { @{ Object = "[WARN]"; ForegroundColor = "Yellow"; NoNewline = $true } }
        "FAIL" { @{ Object = "[FAIL]"; ForegroundColor = "Red";    NoNewline = $true } }
    }

    Write-Host ("`r" + $Indent) -NoNewline
    Write-Host @Status

    $TaskNamePadded = "$TaskNameDisplay".PadRight(58)

    Write-Host "$TaskNamePadded" -NoNewline:($TaskResult -in @("NONE", "OK"))
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
        Show-TaskProgress -TaskName $Name -TaskResult NONE -ToTitleCase:$ToTitleCase
        try {
            # Run `ScriptBlock` logic within `Steps`
            foreach ($Step in $Steps) { & $Step }
            Show-TaskProgress -TaskName $Name -TaskResult OK -ToTitleCase:$ToTitleCase
            Start-Sleep -Milliseconds 400
        } catch {
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
                wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command"

                # Force a sync inside Linux first to flush buffers
                wsl.exe -d $DistroName -u root -- /bin/sh -c "sync"

                # Wait for Windows host to finalise I/O operations
                Start-Sleep -Seconds 2

                $Log = wsl.exe --terminate $DistroName
                if ($LASTEXITCODE -ne 0) { throw " - Failed to terminate $DistroName - $Log" }
            }
        )
    }
}

# -----------------------------------------------------------------------------
# INITIALISATION
# -----------------------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$RootPath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD }
$DEFAULT_WSL_PATH = Join-Path -Path $env:USERPROFILE -ChildPath "WSL\Void"

Clear-Host
Show-Header

# -----------------------------------------------------------------------------
# VALIDATE INPUT
# -----------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InputPath = Read-Host " Enter PATH [$DEFAULT_WSL_PATH]"
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $InstallDirectory = $DEFAULT_WSL_PATH
    } else {
        $InstallDirectory = $InputPath
    }
}

Invoke-Task -Name "Checking PATH" -Critical -Steps @(
    {
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

# -----------------------------------------------------------------------------
# WSL SERVICE CHECKS
# -----------------------------------------------------------------------------

Invoke-Task -Name "Checking ``WslService`` status" -Critical -Steps @(
    {
        $WSLService = Get-Service -Name WslService -ErrorAction Stop
        if ($WSLService.StartupType -eq 'Disabled') {
            Set-Service -Name WslService -StartupType Automatic -ErrorAction Stop
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
        $Response = Invoke-WebRequest -Uri $VOID_CDN -SkipHttpErrorCheck -UseBasicParsing
        if ($Response.StatusCode -ne 200) { throw "$VOID_CDN - HTTP $($Response.StatusCode)" }

        $Versions = $Response.Links |
            Where-Object { $_.href -Like "void-x86_64-ROOTFS*tar.xz" } |
            Select-Object -ExpandProperty href -Unique

        $Script:LatestVersion = $Versions | Select-Object -Last 1

        $Script:VersionString = $Script:LatestVersion |
            Select-String -Pattern '.+([0-9]{4})([0-9]{2})([0-9]{2})\.tar\.xz' |
            ForEach-Object { $_.Matches.Groups[1..3].Value -join "." }

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
        $Content = (Invoke-WebRequest -Uri $CheckSumURL -UseBasicParsing).Content
        if ($content -is [byte[]]) { $Content = [System.Text.Encoding]::UTF8.GetString($Content) }
        $TargetLine = $Content -split "`n" | Where-Object { $_ -match [regex]::Escape($LatestVersion) }
        if (-not $TargetLine) { throw "Hash line not found for $LatestVersion" }
        $RemoteHash = $TargetLine.Split("=")[-1].Trim().ToLower()
        $LocalHash  = (Get-FileHash -Path $TarFile -Algorithm SHA256).Hash.ToLower()
        if ($RemoteHash -ne $LocalHash) {
            Remove-Item $TarFile -Force
            throw "SHA256 mismatch for cached $TarFile (expected $RemoteHash, got $LocalHash). File deleted."
    }
    }
}


$DistroName = "Void-${VersionString}"
$TarFile = Join-Path $RootPath $LatestVersion

if (-not (Test-Path $TarFile)) {
    Invoke-Task -Name "Downloading $LatestVersion" -Critical -Steps @(
        {
            try {
                Invoke-WebRequest -Uri "${VOID_CDN}${LatestVersion}" -OutFile $TarFile -UseBasicParsing
            } catch { throw $_ }
        },
        {
            try {
                $CheckSumURL = "${VOID_CDN}sha256sum.txt"
                $CheckSumContent = (Invoke-WebRequest -Uri "$CheckSumURL" -UseBasicParsing).Content

                if ($CheckSumContent -is [byte[]]) {
                    $CheckSumContent = [System.Text.Encoding]::UTF8.GetString($CheckSumContent)
                }

            } catch { throw $_ }

            $TargetHash = $CheckSumContent -split "`n" | Where-Object { $_ -match [regex]::Escape($LatestVersion) }
            if (-not $TargetHash) {
                throw "Could not identify correct hash for $LatestVersion in $CheckSumURL"
            }

            $RemoteHash = $TargetHash.Split("=")[-1].Trim().ToLower()
            $LocalHash = (Get-FileHash -Path $TarFile -Algorithm SHA256).Hash.ToLower()

            if ($RemoteHash -ne $LocalHash) {
                Remove-Item $TarFile -Force
                throw "SHA256 hash ($RemoteHash) mismatch with $TarFile ($LocalHash)"
            }
        }
    )
} else {
    Invoke-Task -Name "Verifying cached $LatestVersion" -Critical -Steps @(
        { Test-TarfileHash -TarFile $TarFile -CheckSumURL "${VOID_CDN}sha256sum.txt" -LatestVersion $LatestVersion }
    )
}

# -----------------------------------------------------------------------------
# IMPORT VOID LINUX DISTRO
# -----------------------------------------------------------------------------

$ImageDirectory = $null

Invoke-Task -Name "Importing $LatestVersion" -Critical -Steps @(
    {
        # Check existing distributions
        $DistroList = wsl.exe --list --quiet | ForEach-Object { ($_ -replace "`0", "").Trim() }
        if ($DistroList | Select-String -Pattern ([regex]::Escape($DistroName))) {
            throw "'$DistroName' exists; unregister before reinstall - ``wsl --unregister $DistroName``"
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

        $Command = "xbps-install -Syu --yes $($Packages -join ' ')"
        $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1

        # Handle a possible XBPS self-update requirement
        if (($LASTEXITCODE -ne 0) -and ($Log -match "xbps-install -u xbps")) {
            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "xbps-install -Syu xbps --yes" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Failed to self-update ``xbps`` - $Log" }

            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$Command" 2>&1
        }

        if ($LASTEXITCODE -ne 0) { throw "Failed to update indexes & packages - $Log" }
    }
)

# -----------------------------------------------------------------------------
# CONFIGURATION BOOTSTRAP
# -----------------------------------------------------------------------------

Invoke-Task -Name "Importing bootstrap files" -Critical -Steps @(
    {
        $DotConfigPath = Join-Path -Path $RootPath -ChildPath ".config"

        if (Test-Path $DotConfigPath) {
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
            "udevd",        # Device management
            "socklog-unix", # Logging daemon (`/var/log/socklog/`)
            "nanoklogd",    # Kernel logging
            "fcron"         # Cron daemon
        )

        $CommandList = [System.Collections.Generic.List[string]]::new()

        foreach ($Service in $Services) {
            # test -d /etc/sv/$Service && ln -sfn /etc/sv/$Service /etc/runit/runsvdir/default/ || echo "WARN: /etc/sv/$Service not found" >&2
            # Target the persistent `/etc/runit/runsvdir/default/` NOT `/var/service/`
            $CommandList.Add("ln -s /etc/sv/$Service /etc/runit/runsvdir/default/ 2>/dev/null || true")
        }

        if ($CommandList.Count -gt 0) {
            $LinuxCmd = $CommandList -join " && "
            $Log = wsl.exe -d $DistroName -u root -- /bin/sh -c "$LinuxCmd" 2>&1

            if ($LASTEXITCODE -ne 0) { throw "Failed to configure runit services - $Log" }
        }
    },
    {
        <#
        Apply strict log rotation limits to `svlogd` through a `config` file (1MB max, keep 2 files)
        inside EVERY `socklog` subdirectory.
        #>
        $FindSocklog = "find /var/log/socklog/ -maxdepth 1 -type d -not -path /var/log/socklog/"
        $WriteConfig = 'while read -r dir; do echo -e "s1048576\nn2" | tee "$dir/config" > /dev/null; done'
        $Command = "$FindSocklog | $WriteConfig"

        $Log = wsl.exe -d $DistroName -u root -- /bin/bash -c "$Command" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Failed to apply `socklog` policies - $Log" }
    }
)

# -----------------------------------------------------------------------------
# CONFIGURE WINDOWS GIT INTEROP
# -----------------------------------------------------------------------------

Invoke-Task -Name "Configuring Git" -Steps @(
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

Invoke-Task -Name "Creating default user ``void``" -Critical -Steps @(
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
