#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures host NAT and DHCP services for the lab network.

.DESCRIPTION
    Adds the host-side IPv4 gateway to the internal Hyper-V switch, creates a
    Windows NAT object and configures DHCP on the member server. The domain
    controller is used as the DNS server for DHCP clients.
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
Import-Module Hyper-V -ErrorAction Stop
Import-Lab -Name $Config.LabName -NoValidation -ErrorAction Stop

$AdapterAlias = "vEthernet ($($Config.NetworkName))"
$PrefixLength = 24
$NatName = "$($Config.LabName)-NAT"

$ExistingGateway = Get-NetIPAddress `
    -InterfaceAlias $AdapterAlias `
    -AddressFamily IPv4 `
    -ErrorAction SilentlyContinue |
    Where-Object IPAddress -eq $Config.HostGateway

if (-not $ExistingGateway) {
    New-NetIPAddress `
        -InterfaceAlias $AdapterAlias `
        -IPAddress $Config.HostGateway `
        -PrefixLength $PrefixLength | Out-Null
}

$ExistingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if ($ExistingNat) {
    if ($ExistingNat.InternalIPInterfaceAddressPrefix -ne $Config.AddressSpace) {
        throw "NAT '$NatName' already exists with a different address prefix."
    }
}
else {
    New-NetNat `
        -Name $NatName `
        -InternalIPInterfaceAddressPrefix $Config.AddressSpace | Out-Null
}

Invoke-LabCommand `
    -ComputerName $Config.FileServerName `
    -ActivityName 'Configure DHCP server' `
    -ArgumentList `
        $Config.DomainName,
        $Config.FileServerName,
        $Config.FileServerIp,
        $Config.DhcpScopeId,
        $Config.DhcpStartRange,
        $Config.DhcpEndRange,
        $Config.SubnetMask,
        $Config.DhcpScopeName,
        $Config.HostGateway,
        $Config.DomainControllerIp `
    -ScriptBlock {
        param(
            [string]$DomainName,
            [string]$FileServerName,
            [string]$FileServerIp,
            [string]$ScopeId,
            [string]$StartRange,
            [string]$EndRange,
            [string]$SubnetMask,
            [string]$ScopeName,
            [string]$Router,
            [string]$DnsServer
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        if (-not (Get-WindowsFeature -Name DHCP).Installed) {
            Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
        }

        Import-Module DhcpServer -ErrorAction Stop

        $DhcpDnsName = "$FileServerName.$DomainName"
        $Authorization = Get-DhcpServerInDC -ErrorAction SilentlyContinue |
            Where-Object { $_.DnsName -eq $DhcpDnsName -or $_.IPAddress -eq $FileServerIp }

        if (-not $Authorization) {
            Add-DhcpServerInDC -DnsName $DhcpDnsName -IPAddress $FileServerIp
        }

        $Scope = Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue
        if (-not $Scope) {
            Add-DhcpServerv4Scope `
                -Name $ScopeName `
                -StartRange $StartRange `
                -EndRange $EndRange `
                -SubnetMask $SubnetMask `
                -State Active | Out-Null
        }

        Set-DhcpServerv4OptionValue `
            -ScopeId $ScopeId `
            -Router $Router `
            -DnsServer $DnsServer `
            -DnsDomain $DomainName

        Get-DhcpServerv4Scope -ScopeId $ScopeId |
            Select-Object ScopeId, Name, State, StartRange, EndRange
    }

Write-Host '[OK] Host NAT and DHCP services configured.' -ForegroundColor Green
