#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Applies a practical Windows security baseline to the lab systems.

.DESCRIPTION
    Enables all Windows Firewall profiles with inbound blocking, keeps outbound
    traffic allowed, enables firewall logging, verifies Microsoft Defender,
    disables SMBv1, requires SMB signing on servers, enforces RDP NLA and
    configures role-specific inbound firewall rules for the isolated lab subnet.
#>

[CmdletBinding()]
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
Import-Lab -Name $Config.LabName -NoValidation -ErrorAction Stop

$CommonBaseline = {
    param([string]$LabSubnet)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-NetFirewallProfile `
        -Profile Domain, Private, Public `
        -Enabled True `
        -DefaultInboundAction Block `
        -DefaultOutboundAction Allow `
        -LogAllowed True `
        -LogBlocked True

    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        $Defender = Get-MpComputerStatus
        if (-not $Defender.RealTimeProtectionEnabled) {
            Set-MpPreference -DisableRealtimeMonitoring $false
        }
        Set-MpPreference -DisableScriptScanning $false
    }

    Set-ItemProperty `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name UserAuthentication `
        -Type DWord `
        -Value 1

    & wevtutil.exe sl Security /ms:201326592 | Out-Null

    Get-NetFirewallRule -DisplayName 'Lab Managed - *' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule

    New-NetFirewallRule `
        -DisplayName 'Lab Managed - WinRM HTTP' `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 5985 `
        -RemoteAddress $LabSubnet `
        -Profile Domain | Out-Null

    New-NetFirewallRule `
        -DisplayName 'Lab Managed - RDP' `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 3389 `
        -RemoteAddress $LabSubnet `
        -Profile Domain | Out-Null
}

Invoke-LabCommand `
    -ComputerName @($Config.DomainControllerName, $Config.FileServerName, $Config.ClientName) `
    -ActivityName 'Apply common security baseline' `
    -ArgumentList $Config.AddressSpace `
    -ScriptBlock $CommonBaseline

Invoke-LabCommand `
    -ComputerName $Config.DomainControllerName `
    -ActivityName 'Apply domain controller firewall rules' `
    -ArgumentList $Config.AddressSpace `
    -ScriptBlock {
        param([string]$LabSubnet)

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $Rules = @(
            @{ Name='DNS TCP';        Protocol='TCP'; LocalPort='53' }
            @{ Name='DNS UDP';        Protocol='UDP'; LocalPort='53' }
            @{ Name='Kerberos TCP';   Protocol='TCP'; LocalPort='88' }
            @{ Name='Kerberos UDP';   Protocol='UDP'; LocalPort='88' }
            @{ Name='LDAP TCP';       Protocol='TCP'; LocalPort='389' }
            @{ Name='LDAP UDP';       Protocol='UDP'; LocalPort='389' }
            @{ Name='SMB';            Protocol='TCP'; LocalPort='445' }
            @{ Name='RPC Mapper';     Protocol='TCP'; LocalPort='135' }
            @{ Name='Dynamic RPC';    Protocol='TCP'; LocalPort='49152-65535' }
            @{ Name='Global Catalog'; Protocol='TCP'; LocalPort='3268' }
            @{ Name='AD Web Services';Protocol='TCP'; LocalPort='9389' }
        )

        foreach ($Rule in $Rules) {
            New-NetFirewallRule `
                -DisplayName "Lab Managed - $($Rule.Name)" `
                -Direction Inbound `
                -Action Allow `
                -Protocol $Rule.Protocol `
                -LocalPort $Rule.LocalPort `
                -RemoteAddress $LabSubnet `
                -Profile Domain | Out-Null
        }

        Set-SmbServerConfiguration `
            -EnableSMB1Protocol $false `
            -RequireSecuritySignature $true `
            -Force

        Import-Module GroupPolicy -ErrorAction Stop
        $Domain = Get-ADDomain
        $GpoName = 'Lab - Security Baseline'
        $Gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
        if (-not $Gpo) {
            $Gpo = New-GPO -Name $GpoName -Comment 'Managed security baseline for the lab.'
        }

        Set-GPRegistryValue `
            -Name $GpoName `
            -Key 'HKLM\Software\Policies\Microsoft\Windows NT\DNSClient' `
            -ValueName EnableMulticast `
            -Type DWord `
            -Value 0 | Out-Null

        $ExistingLink = (Get-GPInheritance -Target $Domain.DistinguishedName).GpoLinks |
            Where-Object DisplayName -eq $GpoName
        if (-not $ExistingLink) {
            New-GPLink -Name $GpoName -Target $Domain.DistinguishedName -LinkEnabled Yes | Out-Null
        }
    }

Invoke-LabCommand `
    -ComputerName $Config.FileServerName `
    -ActivityName 'Apply file server firewall and SMB rules' `
    -ArgumentList $Config.AddressSpace `
    -ScriptBlock {
        param([string]$LabSubnet)

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        foreach ($Rule in @(
            @{ Name='SMB';      Protocol='TCP'; LocalPort='445' }
            @{ Name='DHCP';     Protocol='UDP'; LocalPort='67' }
            @{ Name='DHCP Reply';Protocol='UDP';LocalPort='68' }
        )) {
            New-NetFirewallRule `
                -DisplayName "Lab Managed - $($Rule.Name)" `
                -Direction Inbound `
                -Action Allow `
                -Protocol $Rule.Protocol `
                -LocalPort $Rule.LocalPort `
                -RemoteAddress $LabSubnet `
                -Profile Domain | Out-Null
        }

        Set-SmbServerConfiguration `
            -EnableSMB1Protocol $false `
            -RequireSecuritySignature $true `
            -Force
    }

Write-Host '[OK] Security baseline applied.' -ForegroundColor Green
