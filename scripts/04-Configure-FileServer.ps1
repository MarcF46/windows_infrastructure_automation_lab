#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures SMB shares and NTFS permissions on the lab file server.

.DESCRIPTION
    Creates one general share and one share per department. Access is assigned
    through domain-local resource groups. The expected AGDLP nesting must exist
    before the file server is changed.
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

$Shares = [System.Collections.Generic.List[hashtable]]::new()
$Shares.Add(@{
    Name          = 'General'
    ResourceGroup = 'DL_General_Data_RW'
    SourceGroup   = 'GG_All_Employees'
})

foreach ($Department in $Config.Departments) {
    $Shares.Add(@{
        Name          = $Department.Key
        ResourceGroup = "DL_$($Department.Key)_Data_RW"
        SourceGroup   = "GG_$($Department.Key)_Employees"
    })
}

$SharesJson = $Shares | ConvertTo-Json -Depth 5 -Compress

# Validate AGDLP before changing the file server.
Invoke-LabCommand `
    -ComputerName $Config.DomainControllerName `
    -ActivityName 'Validate AGDLP groups' `
    -ArgumentList $SharesJson `
    -ScriptBlock {
        param([string]$SharesJson)

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        Import-Module ActiveDirectory -ErrorAction Stop

        $Shares = @($SharesJson | ConvertFrom-Json)
        foreach ($Share in $Shares) {
            $SourceGroup = Get-ADGroup -Identity $Share.SourceGroup -ErrorAction Stop
            $ResourceGroup = Get-ADGroup -Identity $Share.ResourceGroup -ErrorAction Stop

            if ($SourceGroup.GroupScope -ne 'Global') {
                throw "$($Share.SourceGroup) is not a global group."
            }
            if ($ResourceGroup.GroupScope -ne 'DomainLocal') {
                throw "$($Share.ResourceGroup) is not a domain-local group."
            }

            $NestedMembers = @(Get-ADGroupMember -Identity $ResourceGroup -ErrorAction Stop)
            if ($NestedMembers.SamAccountName -notcontains $SourceGroup.SamAccountName) {
                throw "Expected AGDLP nesting is missing: $($Share.SourceGroup) -> $($Share.ResourceGroup)"
            }
        }
    }

Invoke-LabCommand `
    -ComputerName $Config.FileServerName `
    -ActivityName 'Configure file server shares' `
    -ArgumentList $Config.DataRoot, $SharesJson `
    -ScriptBlock {
        param(
            [string]$DataRoot,
            [string]$SharesJson
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $Shares = @($SharesJson | ConvertFrom-Json)
        $DomainNetBios = $env:USERDOMAIN

        if (-not (Get-WindowsFeature -Name FS-FileServer).Installed) {
            Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools | Out-Null
        }

        if (-not (Test-Path -LiteralPath $DataRoot -PathType Container)) {
            New-Item -Path $DataRoot -ItemType Directory -Force | Out-Null
        }

        foreach ($Share in $Shares) {
            $SharePath = Join-Path $DataRoot $Share.Name
            $ResourceAccount = "$DomainNetBios\$($Share.ResourceGroup)"
            $AdminAccount = "$DomainNetBios\Domain Admins"

            if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) {
                New-Item -Path $SharePath -ItemType Directory -Force | Out-Null
            }

            $Acl = New-Object System.Security.AccessControl.DirectorySecurity
            $Acl.SetAccessRuleProtection($true, $false)

            foreach ($Rule in @(
                [System.Security.AccessControl.FileSystemAccessRule]::new(
                    'SYSTEM', 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
                ),
                [System.Security.AccessControl.FileSystemAccessRule]::new(
                    $AdminAccount, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
                ),
                [System.Security.AccessControl.FileSystemAccessRule]::new(
                    $ResourceAccount, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow'
                )
            )) {
                $Acl.AddAccessRule($Rule)
            }

            Set-Acl -LiteralPath $SharePath -AclObject $Acl

            $ExistingShare = Get-SmbShare -Name $Share.Name -ErrorAction SilentlyContinue
            if ($ExistingShare) {
                if ($ExistingShare.Path -ne $SharePath) {
                    throw "Share '$($Share.Name)' already exists with a different path: $($ExistingShare.Path)"
                }
            }
            else {
                New-SmbShare `
                    -Name $Share.Name `
                    -Path $SharePath `
                    -FullAccess $AdminAccount `
                    -ChangeAccess $ResourceAccount `
                    -FolderEnumerationMode AccessBased | Out-Null
            }
        }

        Get-SmbShare |
            Where-Object Name -in $Shares.Name |
            Select-Object Name, Path, FolderEnumerationMode
    }

Write-Host '[OK] File server shares and permissions configured.' -ForegroundColor Green
