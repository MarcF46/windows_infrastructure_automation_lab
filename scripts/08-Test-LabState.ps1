#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Verifies the final state of the Windows infrastructure lab.

.DESCRIPTION
    Performs read-only checks for VM state, Active Directory, SMB shares,
    DHCP, Windows Firewall, Microsoft Defender and selected security settings.
    Results are written as structured objects for easy review and reporting.
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

$Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [string]$Category,
        [string]$Check,
        [bool]$Passed,
        [string]$Details
    )

    $Results.Add([pscustomobject]@{
        Category = $Category
        Check    = $Check
        Passed   = $Passed
        Details  = $Details
    })
}

foreach ($VmName in @($Config.DomainControllerName, $Config.FileServerName, $Config.ClientName)) {
    $Vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
    Add-Result `
        -Category 'Hyper-V' `
        -Check "$VmName running" `
        -Passed ($null -ne $Vm -and $Vm.State -eq 'Running') `
        -Details $(if ($Vm) { "State=$($Vm.State); Uptime=$($Vm.Uptime)" } else { 'VM not found' })
}

$AdOutput = Invoke-LabCommand `
    -ComputerName $Config.DomainControllerName `
    -ActivityName 'Verify Active Directory' `
    -PassThru `
    -ScriptBlock {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        Import-Module ActiveDirectory -ErrorAction Stop

        $Domain = Get-ADDomain
        $RootOu = Get-ADOrganizationalUnit `
            -Identity "OU=Company,$($Domain.DistinguishedName)" `
            -ErrorAction SilentlyContinue

        [pscustomobject]@{
            ResultType        = 'AdVerification'
            Domain            = $Domain.DNSRoot
            RootOuExists      = $null -ne $RootOu
            GlobalGroupCount  = @(Get-ADGroup -Filter 'Name -like "GG_*"').Count
            ResourceGroupCount= @(Get-ADGroup -Filter 'Name -like "DL_*"').Count
            EnabledUserCount  = @(Get-ADUser -Filter 'Enabled -eq $true').Count
        }
    }

$Ad = $AdOutput | Where-Object ResultType -eq 'AdVerification' | Select-Object -Last 1
Add-Result -Category 'Active Directory' -Check 'Expected domain' -Passed ($Ad.Domain -eq $Config.DomainName) -Details $Ad.Domain
Add-Result -Category 'Active Directory' -Check 'Managed OU structure' -Passed $Ad.RootOuExists -Details 'OU=Company'
Add-Result -Category 'Active Directory' -Check 'Global groups present' -Passed ($Ad.GlobalGroupCount -ge 6) -Details "$($Ad.GlobalGroupCount) global groups"
Add-Result -Category 'Active Directory' -Check 'Resource groups present' -Passed ($Ad.ResourceGroupCount -ge 6) -Details "$($Ad.ResourceGroupCount) domain-local groups"

$FileOutput = Invoke-LabCommand `
    -ComputerName $Config.FileServerName `
    -ActivityName 'Verify file and network services' `
    -ArgumentList $Config.DhcpScopeId `
    -PassThru `
    -ScriptBlock {
        param([string]$DhcpScopeId)

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $ShareNames = @('General','Finance','HR','IT','Operations','Sales')
        $Shares = @(Get-SmbShare | Where-Object Name -in $ShareNames)
        $Smb = Get-SmbServerConfiguration
        $DhcpScope = Get-DhcpServerv4Scope -ScopeId $DhcpScopeId -ErrorAction SilentlyContinue
        $Firewall = Get-NetFirewallProfile
        $Defender = if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
            Get-MpComputerStatus
        }

        [pscustomobject]@{
            ResultType             = 'FileServerVerification'
            ShareCount             = $Shares.Count
            Smb1Enabled            = [bool]$Smb.EnableSMB1Protocol
            SmbSigningRequired     = [bool]$Smb.RequireSecuritySignature
            DhcpScopeActive        = $null -ne $DhcpScope -and $DhcpScope.State -eq 'Active'
            FirewallProfilesEnabled= @($Firewall | Where-Object Enabled -eq $true).Count
            DefenderRealtime       = if ($Defender) { [bool]$Defender.RealTimeProtectionEnabled } else { $null }
        }
    }

$File = $FileOutput | Where-Object ResultType -eq 'FileServerVerification' | Select-Object -Last 1
Add-Result -Category 'File Server' -Check 'Expected SMB shares' -Passed ($File.ShareCount -eq 6) -Details "$($File.ShareCount) shares"
Add-Result -Category 'Security' -Check 'SMBv1 disabled' -Passed (-not $File.Smb1Enabled) -Details "SMB1=$($File.Smb1Enabled)"
Add-Result -Category 'Security' -Check 'SMB signing required' -Passed $File.SmbSigningRequired -Details "Required=$($File.SmbSigningRequired)"
Add-Result -Category 'DHCP' -Check 'DHCP scope active' -Passed $File.DhcpScopeActive -Details $Config.DhcpScopeId
Add-Result -Category 'Security' -Check 'All firewall profiles enabled' -Passed ($File.FirewallProfilesEnabled -eq 3) -Details "$($File.FirewallProfilesEnabled)/3 profiles"
if ($null -ne $File.DefenderRealtime) {
    Add-Result -Category 'Security' -Check 'Defender real-time protection' -Passed $File.DefenderRealtime -Details "Enabled=$($File.DefenderRealtime)"
}

$Results | Sort-Object Category, Check | Format-Table -AutoSize -Wrap

$Failed = @($Results | Where-Object { -not $_.Passed })
if ($Failed.Count -gt 0) {
    throw "Lab verification failed: $($Failed.Count) check(s) did not pass."
}

Write-Host '[OK] All verification checks passed.' -ForegroundColor Green
