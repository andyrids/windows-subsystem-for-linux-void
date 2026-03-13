set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]

[default]
[doc("Shorthand for `just --list`")]
_list:
    @just --list

[doc("Elevated privileges check")]
_isadmin:
    #!pwsh.exe
    $identify = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identify.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
      Write-Host "Recipe requires Administrator privileges" -BackgroundColor Red -ForegroundColor Black
      exit 1
    }

[doc("`Get-ExecutionPolicy` check")]
_isexecution:
    #!pwsh.exe
    $ExecutionPolicy = (Get-ExecutionPolicy).ToString()
    if ($ExecutionPolicy -notin @('RemoteSigned', 'AllSigned', 'Unrestricted')) {
    	Write-Host "Execution policy must be 'RemoteSigned', 'AllSigned' or 'Unrestricted'"
    	Write-Host "Run ``Set-ExecutionPolicy AllSigned``"
    	exit 1
    }

[doc("Run `Install-VoidLinux.ps1`")]
install: _isadmin _isexecution
    #!pwsh.exe
    & .\Install-VoidLinux.ps1

[doc("Run `PSScriptAnalyzer` on `Install-VoidLinux.ps1`")]
analyse:
    #!pwsh.exe
    Invoke-ScriptAnalyzer -Path ".\Install-VoidLinux.ps1" -Settings ".\PSScriptAnalyzerSettings.psd1" -ReportSummary
