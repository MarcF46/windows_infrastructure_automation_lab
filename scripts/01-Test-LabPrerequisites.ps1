#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Validates the local host before the Windows infrastructure lab is deployed.

.DESCRIPTION
    Checks administrative privileges, required PowerShell modules, Hyper-V,
    AutomatedLab, ISO files, LabSources registration, disk space and memory.

    The script is read-only. It does not create or modify lab resources.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-CheckResult {
    param(
        [Parameter(Mandatory)]
        [string]$Check,
        [Parameter(Mandatory)]
        [bool]$Passed,
        [Parameter(Mandatory)]
        [string]$Details
    )

    [pscustomobject]@{
        Check   = $Check
        Passed  = $Passed
        Details = $Details
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration file not found: $ConfigPath. Copy config/lab.example.psd1 to config/lab.psd1 and adjust local paths."
}

$Config = Import-PowerShellDataFile -LiteralPath $ConfigPath
$Results = [System.Collections.Generic.List[object]]::new()

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
$IsAdministrator = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$Results.Add((Write-CheckResult -Check 'Administrator' -Passed $IsAdministrator -Details "User: $($Identity.Name)"))

$PowerShellOk = $PSVersionTable.PSVersion.Major -ge 7
$Results.Add((Write-CheckResult -Check 'PowerShell 7+' -Passed $PowerShellOk -Details $PSVersionTable.PSVersion.ToString()))

foreach ($ModuleName in @('AutomatedLab', 'Hyper-V')) {
    $Module = Get-Module -ListAvailable -Name $ModuleName |
        Sort-Object Version -Descending |
        Select-Object -First 1

    $Results.Add((Write-CheckResult `
        -Check "Module: $ModuleName" `
        -Passed ($null -ne $Module) `
        -Details $(if ($Module) { $Module.Version.ToString() } else { 'Not installed' })))
}

try {
    $Vmms = Get-Service -Name vmms -ErrorAction Stop
    $VmHost = Get-VMHost -ErrorAction Stop
    $HyperVOk = $Vmms.Status -eq 'Running'
    $HyperVDetails = "VMMS=$($Vmms.Status); VMPath=$($VmHost.VirtualMachinePath)"
}
catch {
    $HyperVOk = $false
    $HyperVDetails = $_.Exception.Message
}
$Results.Add((Write-CheckResult -Check 'Hyper-V runtime' -Passed $HyperVOk -Details $HyperVDetails))

foreach ($IsoPath in @($Config.ServerIsoPath, $Config.ClientIsoPath)) {
    $Exists = Test-Path -LiteralPath $IsoPath -PathType Leaf
    $Results.Add((Write-CheckResult -Check "ISO: $(Split-Path $IsoPath -Leaf)" -Passed $Exists -Details $IsoPath))
}

try {
    Import-Module AutomatedLab -ErrorAction Stop
    $RegisteredLabSources = [string](Get-LabSourcesLocation -Local)
    $LabSourcesOk = $RegisteredLabSources.TrimEnd('\') -eq $Config.LabSourcesPath.TrimEnd('\')
    $Results.Add((Write-CheckResult -Check 'LabSources path' -Passed $LabSourcesOk -Details $RegisteredLabSources))
}
catch {
    $Results.Add((Write-CheckResult -Check 'LabSources path' -Passed $false -Details $_.Exception.Message))
}

$SystemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
$OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
$FreeDiskGb = [math]::Round($SystemDrive.FreeSpace / 1GB, 2)
$FreeMemoryGb = [math]::Round(($OperatingSystem.FreePhysicalMemory * 1KB) / 1GB, 2)

$Results.Add((Write-CheckResult -Check 'Free disk space' -Passed ($FreeDiskGb -ge 80) -Details "$FreeDiskGb GB free on C:"))
$Results.Add((Write-CheckResult -Check 'Free memory' -Passed ($FreeMemoryGb -ge 7) -Details "$FreeMemoryGb GB currently free"))

$Results | Format-Table -AutoSize -Wrap

$Failed = @($Results | Where-Object { -not $_.Passed })
if ($Failed.Count -gt 0) {
    throw "Prerequisite validation failed: $($Failed.Count) check(s) did not pass."
}

Write-Host '[OK] All prerequisite checks passed.' -ForegroundColor Green
