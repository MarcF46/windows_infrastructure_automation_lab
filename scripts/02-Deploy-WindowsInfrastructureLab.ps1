#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Deploys a three-VM Windows infrastructure lab with AutomatedLab and Hyper-V.

.DESCRIPTION
    Creates one domain controller, one member/file server and one Windows client.
    The lab uses an internal Hyper-V network and a dedicated Active Directory domain.

    No password is stored in the repository. The lab administrator password is
    requested interactively and exists in plaintext only for the short period in
    which AutomatedLab requires it for the lab definition.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:AUTOMATEDLAB_TELEMETRY_OPTIN = 'false'

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration file not found: $ConfigPath"
}

$Config = Import-PowerShellDataFile -LiteralPath $ConfigPath
Import-Module AutomatedLab -ErrorAction Stop
Import-Module Hyper-V -ErrorAction Stop

$PlannedVmNames = @(
    $Config.DomainControllerName
    $Config.FileServerName
    $Config.ClientName
)

$ExistingVms = @(Get-VM -Name $PlannedVmNames -ErrorAction SilentlyContinue)
if ($ExistingVms.Count -gt 0) {
    throw "VM name collision detected: $($ExistingVms.Name -join ', ')"
}

if (Get-VMSwitch -Name $Config.NetworkName -ErrorAction SilentlyContinue) {
    throw "A Hyper-V switch named '$($Config.NetworkName)' already exists."
}

$ExistingLabs = @(Get-Lab -List -ErrorAction Stop | ForEach-Object {
    if ($_ -is [string]) { $_ } elseif ($_.PSObject.Properties['Name']) { $_.Name } else { [string]$_ }
})
if ($ExistingLabs -contains $Config.LabName) {
    throw "An AutomatedLab definition named '$($Config.LabName)' already exists."
}

foreach ($Path in @($Config.ServerIsoPath, $Config.ClientIsoPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required ISO file not found: $Path"
    }
}

if (-not $PSCmdlet.ShouldProcess($Config.LabName, 'Create AutomatedLab definition and deploy virtual machines')) {
    return
}

$SecurePassword = Read-Host 'Enter the LabAdmin password' -AsSecureString
$ConfirmPassword = Read-Host 'Confirm the LabAdmin password' -AsSecureString

$PlainPassword = [System.Net.NetworkCredential]::new('', $SecurePassword).Password
$PlainPasswordConfirmation = [System.Net.NetworkCredential]::new('', $ConfirmPassword).Password

try {
    if ($PlainPassword -ne $PlainPasswordConfirmation) {
        throw 'The password confirmation does not match.'
    }

    $PasswordMeetsRequirements = (
        $PlainPassword.Length -ge 12 -and
        $PlainPassword -cmatch '[A-Z]' -and
        $PlainPassword -cmatch '[a-z]' -and
        $PlainPassword -match '[0-9]' -and
        $PlainPassword -match '[^a-zA-Z0-9]'
    )

    if (-not $PasswordMeetsRequirements) {
        throw 'The password must contain at least 12 characters, upper- and lowercase letters, a number and a special character.'
    }

    New-LabDefinition `
        -Name $Config.LabName `
        -VmPath $Config.VmRootPath `
        -ReferenceDiskSizeInGB 80 `
        -DefaultVirtualizationEngine HyperV `
        -Notes @{
            Purpose  = 'Windows infrastructure automation portfolio lab'
            Domain   = $Config.DomainName
            Network  = $Config.AddressSpace
            Platform = 'Hyper-V / AutomatedLab'
        }

    Add-LabVirtualNetworkDefinition `
        -Name $Config.NetworkName `
        -AddressSpace $Config.AddressSpace `
        -VirtualizationEngine HyperV

    Add-LabDomainDefinition `
        -Name $Config.DomainName `
        -AdminUser $Config.DomainAdminUser `
        -AdminPassword $PlainPassword

    Set-LabInstallationCredential `
        -Username $Config.DomainAdminUser `
        -Password $PlainPassword

    $ServerHyperVProperties = @{
        AutomaticStartAction = 'Nothing'
        AutomaticStopAction  = 'Save'
        EnableSecureBoot     = 'On'
        SecureBootTemplate   = 'MicrosoftWindows'
    }

    $ClientHyperVProperties = @{
        AutomaticStartAction = 'Nothing'
        AutomaticStopAction  = 'Save'
        EnableSecureBoot     = 'On'
        SecureBootTemplate   = 'MicrosoftWindows'
        EnableTpm            = 'True'
    }

    Add-LabMachineDefinition `
        -Name $Config.DomainControllerName `
        -OperatingSystem $Config.ServerOsName `
        -Memory 1536MB `
        -MinMemory 1GB `
        -MaxMemory 2GB `
        -Processors 2 `
        -Network $Config.NetworkName `
        -IpAddress $Config.DomainControllerIp `
        -DnsServer1 $Config.DomainControllerIp `
        -DomainName $Config.DomainName `
        -Roles RootDC `
        -VmGeneration 2 `
        -HypervProperties $ServerHyperVProperties

    Add-LabMachineDefinition `
        -Name $Config.FileServerName `
        -OperatingSystem $Config.ServerOsName `
        -Memory 1536MB `
        -MinMemory 1GB `
        -MaxMemory 2GB `
        -Processors 2 `
        -Network $Config.NetworkName `
        -IpAddress $Config.FileServerIp `
        -DnsServer1 $Config.DomainControllerIp `
        -DomainName $Config.DomainName `
        -Roles FileServer `
        -VmGeneration 2 `
        -HypervProperties $ServerHyperVProperties

    Add-LabMachineDefinition `
        -Name $Config.ClientName `
        -OperatingSystem $Config.ClientOsName `
        -Memory 4GB `
        -MinMemory 2GB `
        -MaxMemory 4GB `
        -Processors 2 `
        -Network $Config.NetworkName `
        -IpAddress $Config.ClientIp `
        -DnsServer1 $Config.DomainControllerIp `
        -DomainName $Config.DomainName `
        -VmGeneration 2 `
        -HypervProperties $ClientHyperVProperties

    Write-Host '[INFO] Lab definition created. Starting deployment...' -ForegroundColor Cyan
    Install-Lab

    Write-Host '[OK] Base infrastructure deployment completed.' -ForegroundColor Green
    Get-LabVM -All | Select-Object Name, DomainName, IpV4Address, OperatingSystem | Format-Table -AutoSize
}
finally {
    $PlainPassword = $null
    $PlainPasswordConfirmation = $null
    $SecurePassword = $null
    $ConfirmPassword = $null
}
