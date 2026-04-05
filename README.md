# Windows Subsystem For Linux (WSL) - Void

This repository contains a Powershell bootstrap script, which automates the installation and configuration of Void Linux on WSL.

> [!NOTE]
> **WIP**: This repository was recently refined & updated.

![Installation complete](/docs/img/void-linux.png)

## **Features**

* **Void CDN**: Scrapes the Void Linux CDN & downloads the latest x86_64 ROOTFS tarball.
* **Bootstrap Configuration**: Copies local bootstrap files (`.config/`) to the distro.
* **Linux Skeleton Files**: Ensures each new user starts with default dotfiles (`.bashrc`, `.vimrc`, etc.).
* **Configures runit**: Configures the `runit` init system and essential services (`udevd`, `socklog`, `fcron`) for WSL.
* **Configures Default User**: Automatically provisions a default `void` user with passwordless sudo.
* **Configures Git**: Mirrors Windows Git user.name, user.email & Windows Git Credential Manager config.
* **System Information**: Fetches & displays system information with `fastfetch`.
* **Persistent Logging**: Configures `socklog` for robust, persistent system logging with strict file size rotation.
* **CRLF to LF Normalization**: Automatically converts Windows line endings to Unix standard using `dos2unix`.

---

> [!WARNING]
> The script requires:
> 1. **Windows 10/11** with `WSL2` enabled
> 2. **PowerShell 5.1**/**PowerShell 7+**
> 3. Administrative privileges

## Quick Start

Open a `PowerShell` terminal as **Administrator** and clone this repository.

```ps1
git clone --depth=1 git@github.com:andyrids/windows-subsystem-for-linux-void.git
```

Run the `PowerShell` installation script.

```ps1
cd .\windows-subsystem-for-linux-void\
. Install-VoidLinux.ps1
```

If you have `Just` installed, there is a [`justfile`](Justfile) provided with an `install` recipe. 

```ps1
cd .\windows-subsystem-for-linux-void\
just install
```

> [!TIP]
> - Install [Just](https://github.com/casey/just) via `winget install --id Casey.Just --exact`.

## Detailed Configuration Steps

There can be some nuance and extra setup involved when manually installing distros onto WSL. This is especially true in the case of Void Linux, which uses the `runit` init system instead of the `Systemd` system and service manager. `Systemd` is fully supported by WSL out-of-the-box, whereas `runit` needs specific manual configuration via `/etc/wsl.conf`.

The exact commands used are available within the [Install-VoidLinux.ps1](Install-VoidLinux.ps1) script.

### Configuration Files

All Linux configuration files and scripts are placed within the repo `.config` directory and mirror the paths within the distribution. for example, `.config/etc/fstab` would be placed at `/etc/fstab` during the bootstrap.

```
└───.config <- Void configuration files
    ├───etc
    │   │   fstab     <- Filesystem table (tmpfs for /tmp)
    │   │   profile   <- Default profile configuration & $PATH
    │   │   wsl.conf  <- Default WSL distro configuration (triggers runit)
    │   │
    │   ├───ld.so.conf.d
    │   │       ld.wsl.conf <- WSL dynamic linker configuration
    │   │
    │   ├───profile.d
    │   │       colours.sh <- Terminal colour support script
    │   │
    │   ├───runit
    │   │   └───core-services
    │   │           99-cleanup.sh <- runit initialization cleanup script
    │   │
    │   ├───skel <- Linux 'skeleton' directory
    │   │   │   .bashrc       <- Environment variables & aliases
    │   │   │   .bash_logout  <- Cleans history
    │   │   │   .bash_profile <- Loads `.bashrc` & runs `fastfetch`
    │   │   │   .vimrc        <- Sensible default Vim configuration
    │   │   │
    │   │   └───.config
    │   │       ├───fastfetch
    │   │       │       config.jsonc <- fastfetch config
    │   │       │
    │   │       ├───git
    │   │       │       config <- Git default settings
    │   │       │
    │   │       └───just
    │   │               justfile <- Default just recipes
    │   │
    │   └───udev
    │       └───rules.d
    │               60-micropython-rpi.rules <- ttyACM rules for Raspberry Pi
    │
    ├───usr
    │   └───share
    │       └───wsl
    │               
    │
    └───var
        └───log
            └───socklog
                    config <- Strict log rotation limits (1MB, 2 files)
```

### (1) Environment Validation & Download

The script first checks if the `WslService` is running, enabling it if necessary. It queries the official Void Linux [live CDN](https://repo-default.voidlinux.org/live/current/) to identify the latest available ROOTFS tarball. The remote SHA256 hash is compared with the downloaded tarball hash, raising a critical error on mismatch.

### (2) Distribution Import

The downloaded tarball is imported using `wsl.exe --import`. If `-InstallDirectory` is not provided, the script now defaults automatically to `%USERPROFILE%\WSL\Void` (no interactive path prompt).

```ps1
. .\windows-subsystem-for-linux-void\Install-VoidLinux.ps1 -InstallDirectory "C:\WSL\Void"
```

You can also provide a custom distro name with `-DistroName` to run a side-by-side test installation without unregistering an existing Void distro.

```ps1
. .\windows-subsystem-for-linux-void\Install-VoidLinux.ps1 -DistroName "Void-Test"
```

If the default distro name already exists and `-DistroName` is not set, the script prompts for a unique name.

![install directory](/docs/img/install-directory-check.png)

### (3) Package Repository Update & Upgrades

The script executes `xbps-install -Syu` to update the Void package indexes and upgrade the base system. It handles instances where the package manager (`xbps`) requires a self-update before proceeding.

After the upgrade, the following packages are installed:

- **util-linux** - low-level system utilities
- **base-devel** - essential tools required to compile from source
- **fastfetch** - system information tool (`neofetch` replacement)
- **git** - version control system
- **just** - command runner for project-specific commands
- ***python*** - latest Python version
- **python3-devel** - enables compiling Python modules
- **tree** - recursively lists directory contents
- **fcron** - task scheduler (`cron` implementation)
- **vim** - terminal-based text editor
- **wget** - command-line utility for downloading files
- **socklog** - `syslog` replacement that integrates perfectly with `runit`
- **socklog-void** - Void-specific integration package for `socklog`
- **dos2unix** - utility used to convert text files between DOS/Windows format

### (4) Configuration Overlay

The script treats the `.config` directory as the root of the Linux filesystem (/). It archives the local files, pipes them into the WSL distro via `tar`, and extracts them into `/tmp/bootstrap`.

`dos2unix` is ran over all files in the staging directory to guarantee that any CRLF line endings are converted to native LF format. It then copies the files to their final destinations and fixes permissions inside `/etc/skel`.

### (5) Runit Services & Configuration

Void Linux utilizes the `runit` init system. To boot it properly under WSL, the overlay includes an `/etc/wsl.conf` with `command = "/etc/runit/1 && (/etc/runit/2 &)"` in the `[boot]` section.

The script provisions services by symbolically linking them from `/etc/sv/` directly into the persistent `/etc/runit/runsvdir/default/` directory (avoiding the standard `/var/service/` which does not persist across WSL reboots).

Enabled services:

- `udevd` (Device management)
- `socklog-unix` (System logging daemon)
- `nanoklogd` (Kernel logging)
- `fcron` (Cron daemon)

A strict logging policy is applied by writing a `config` file into every `socklog` output directory, ensuring logs don't consume endless disk space (limited to 1MB per file, retaining 2 archives).

### (6) Interoperability With Git For Windows

On Windows, Git usually sets `credential.helper` to 'manager' which resolves to 'credential-manager' and relates to the Git Credential Manager (GCM) that ships with Git. Typically, `git.exe` is found at `C:\Program Files\Git\cmd` and GCM would therefore be found at `C:\Program Files\Git\mingw64\bin\`.

The script checks to see if Git is installed on Windows and attempts to identify the GCM path. It also checks the `user.name` and `user.email` config values. The skeleton Git config is updated with the `user.name` and `user.email` values from Windows Git config (if present) and `credential.helper` is set to the absolute WSL path for the GCM executable on Windows.

This enables GCM to be used to by Git within the Void distro. You can still manually create SSH keys and manage them as you see fit.

### (7) Creating The Default User

The script provisions a standard user named `void` with `bash` as the default shell. This user is added to the `wheel`, `dialout`, and `socklog` groups.

Passwordless `sudo` access is granted by creating an isolated `/etc/sudoers.d/wheel` file, keeping the system secure while avoiding `sed` manipulations of the main sudoers configuration.

### (8) Custom udev Rules

Included in the configuration are custom `udev` rules targeting standard hardware devices like Raspberry Pi Pico/MicroPython boards. These rules ensure proper detection over the ttyACM abstract control model, placing the devices accurately in the dialout group for user-level access.

I have a Python TUI (Text-based User Interface), which uses `usbipd-win` (`winget install usbipd`) to attach devices to WSL and can facilitate connections within your WSL distros. If you would prefer a TUI over the traditional CLI, the GitHub project is located at [andyrids/picolynx](https://github.com/andyrids/picolynx).

### (9) Terminate Distro

The Void distro undergoes a structured shutdown sequence. A script is triggered inside WSL to halt `runsvdir` (the `runit` supervisor) cleanly and flush disk buffers with sync. Finally, `wsl --terminate` is executed, preparing the instance for interactive use.

## Debugging & Useful Commands

| Command                                      | Description                                             |
| -------------------------------------------- | ------------------------------------------------------- |
| sudo sv status /var/service/*                | Display `runit` services & uptime status                |
| sudo tail -f /var/log/socklog/daemon/current | Display live streaming system daemon logs               |
| sudo xbps-install -Su                        | Update repositories & upgrade packages                  |
| xbps-query -Rs <package>                     | Search remote repositories for a specific package       |
| xbps-query -l                                | List installed packages                                 |
| sudo xbps-remove -Ro <package>               | Remove package & any sole dependencies for that package |
| sudo xbps-remove -Oo                         | Remove system-wide orphaned packages                    |
| just -g                                      | List recipes in the `$HOME/.config/just/Justfile`       |

There is a global `$HOME/.config/just/Justfile`, which contains some potentially useful recipes. The documentation for these recipes can be displayed with the `just -g` command. The recipes within this file can be ran using `just -g <recipe-name>`.

```bash
just -g
```

![Justfile](/docs/img/justfile-recipes.png)

For example, there is a recipe for the installation of the Astral `uv` Python package manager and for `pnpm`. To install `uv`, `pnpm` and the LTS version of `Node.js`, you could run the following recipes:

```bash
just -g install-uv
just -g install-pnpm
just -g pnpm-env
```
