#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Creates the Active Directory structure for the Windows infrastructure lab.

.DESCRIPTION
    Creates protected organizational units, global role groups, domain-local
    resource groups and sample users. The script also builds AGDLP nesting and
    moves the member server and client computer accounts into managed OUs.

    The script is designed to be idempotent. Existing objects are reused when
    their type and location match the expected configuration.
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

$InitialPassword = Read-Host 'Enter the initial password for new sample users' -AsSecureString
$PlainPassword = [System.Net.NetworkCredential]::new('', $InitialPassword).Password

try {
    if ($PlainPassword.Length -lt 12) {
        throw 'The sample-user password must contain at least 12 characters.'
    }

    $DepartmentsJson = $Config.Departments | ConvertTo-Json -Depth 5 -Compress

    Invoke-LabCommand `
        -ComputerName $Config.DomainControllerName `
        -ActivityName 'Initialize Active Directory structure' `
        -ArgumentList $Config.DomainName, $Config.FileServerName, $Config.ClientName, $DepartmentsJson, $PlainPassword `
        -ScriptBlock {
            param(
                [string]$DomainName,
                [string]$FileServerName,
                [string]$ClientName,
                [string]$DepartmentsJson,
                [string]$UserPassword
            )

            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'
            Import-Module ActiveDirectory -ErrorAction Stop

            $Departments = @($DepartmentsJson | ConvertFrom-Json)
            $Domain = Get-ADDomain -ErrorAction Stop
            if ($Domain.DNSRoot -ne $DomainName) {
                throw "Unexpected domain: $($Domain.DNSRoot)"
            }

            $RootDn = $Domain.DistinguishedName
            $ManagedRootName = 'Company'
            $ManagedRootDn = "OU=$ManagedRootName,$RootDn"

            function Ensure-OrganizationalUnit {
                param(
                    [Parameter(Mandatory)][string]$Name,
                    [Parameter(Mandatory)][string]$Path,
                    [string]$Description = ''
                )

                $Dn = "OU=$Name,$Path"
                $Existing = Get-ADOrganizationalUnit -Identity $Dn -ErrorAction SilentlyContinue
                if (-not $Existing) {
                    New-ADOrganizationalUnit `
                        -Name $Name `
                        -Path $Path `
                        -Description $Description `
                        -ProtectedFromAccidentalDeletion $true | Out-Null
                }
                return $Dn
            }

            function Ensure-Group {
                param(
                    [Parameter(Mandatory)][string]$Name,
                    [Parameter(Mandatory)][ValidateSet('Global','DomainLocal')][string]$Scope,
                    [Parameter(Mandatory)][string]$Path,
                    [string]$Description = ''
                )

                $Existing = Get-ADGroup -Filter "SamAccountName -eq '$Name'" -ErrorAction Stop
                if (-not $Existing) {
                    New-ADGroup `
                        -Name $Name `
                        -SamAccountName $Name `
                        -GroupScope $Scope `
                        -GroupCategory Security `
                        -Path $Path `
                        -Description $Description | Out-Null
                }
            }

            Ensure-OrganizationalUnit -Name $ManagedRootName -Path $RootDn -Description 'Managed lab objects' | Out-Null
            $UsersOu = Ensure-OrganizationalUnit -Name 'Users' -Path $ManagedRootDn -Description 'Managed user accounts'
            $ComputersOu = Ensure-OrganizationalUnit -Name 'Computers' -Path $ManagedRootDn -Description 'Managed client computers'
            $ServersOu = Ensure-OrganizationalUnit -Name 'Servers' -Path $ManagedRootDn -Description 'Managed member servers'
            $GroupsOu = Ensure-OrganizationalUnit -Name 'Groups' -Path $ManagedRootDn -Description 'Security and resource groups'
            Ensure-OrganizationalUnit -Name 'Administrators' -Path $ManagedRootDn -Description 'Privileged accounts' | Out-Null
            Ensure-OrganizationalUnit -Name 'ServiceAccounts' -Path $ManagedRootDn -Description 'Service accounts' | Out-Null
            Ensure-OrganizationalUnit -Name 'DisabledObjects' -Path $ManagedRootDn -Description 'Disabled accounts and computers' | Out-Null

            foreach ($Department in $Departments) {
                Ensure-OrganizationalUnit `
                    -Name $Department.Key `
                    -Path $UsersOu `
                    -Description "$($Department.DisplayName) users" | Out-Null
            }

            Ensure-Group -Name 'GG_All_Employees' -Scope Global -Path $GroupsOu -Description 'All lab employees'
            Ensure-Group -Name 'DL_General_Data_RW' -Scope DomainLocal -Path $GroupsOu -Description 'Write access to the general data share'

            foreach ($Department in $Departments) {
                $GlobalGroup = "GG_$($Department.Key)_Employees"
                $ResourceGroup = "DL_$($Department.Key)_Data_RW"

                Ensure-Group -Name $GlobalGroup -Scope Global -Path $GroupsOu -Description "$($Department.DisplayName) employees"
                Ensure-Group -Name $ResourceGroup -Scope DomainLocal -Path $GroupsOu -Description "Write access to $($Department.DisplayName) data"

                Add-ADGroupMember -Identity 'GG_All_Employees' -Members $GlobalGroup -ErrorAction SilentlyContinue
                Add-ADGroupMember -Identity $ResourceGroup -Members $GlobalGroup -ErrorAction SilentlyContinue
            }

            Add-ADGroupMember -Identity 'DL_General_Data_RW' -Members 'GG_All_Employees' -ErrorAction SilentlyContinue

            $SampleUsers = @(
                @{ GivenName='Erika'; Surname='Mustermann'; Sam='erika.mustermann'; Department='HR';         Title='HR Specialist' }
                @{ GivenName='Max';   Surname='Beispiel';   Sam='max.beispiel';    Department='Finance';    Title='Finance Specialist' }
                @{ GivenName='Nina';  Surname='Demo';       Sam='nina.demo';       Department='IT';         Title='Systems Administrator' }
                @{ GivenName='Tim';   Surname='Muster';     Sam='tim.muster';      Department='Operations'; Title='Operations Specialist' }
                @{ GivenName='Lisa';  Surname='Test';       Sam='lisa.test';       Department='Sales';      Title='Sales Specialist' }
            )

            $SecureUserPassword = ConvertTo-SecureString -String $UserPassword -AsPlainText -Force

            foreach ($User in $SampleUsers) {
                $ExistingUser = Get-ADUser -Filter "SamAccountName -eq '$($User.Sam)'" -ErrorAction Stop
                $UserOu = "OU=$($User.Department),$UsersOu"

                if (-not $ExistingUser) {
                    New-ADUser `
                        -Name "$($User.GivenName) $($User.Surname)" `
                        -GivenName $User.GivenName `
                        -Surname $User.Surname `
                        -DisplayName "$($User.GivenName) $($User.Surname)" `
                        -SamAccountName $User.Sam `
                        -UserPrincipalName "$($User.Sam)@$DomainName" `
                        -Department $User.Department `
                        -Title $User.Title `
                        -Path $UserOu `
                        -AccountPassword $SecureUserPassword `
                        -Enabled $true `
                        -ChangePasswordAtLogon $true
                }

                Add-ADGroupMember -Identity "GG_$($User.Department)_Employees" -Members $User.Sam -ErrorAction SilentlyContinue
            }

            foreach ($ComputerMove in @(
                @{ Name = $FileServerName; Destination = $ServersOu }
                @{ Name = $ClientName; Destination = $ComputersOu }
            )) {
                $Computer = Get-ADComputer -Identity $ComputerMove.Name -ErrorAction Stop
                if ($Computer.DistinguishedName -notlike "*,$($ComputerMove.Destination)") {
                    Move-ADObject -Identity $Computer.DistinguishedName -TargetPath $ComputerMove.Destination
                }
            }

            [pscustomobject]@{
                Domain             = $Domain.DNSRoot
                ManagedRoot        = $ManagedRootDn
                DepartmentCount    = $Departments.Count
                SampleUserCount    = $SampleUsers.Count
                GlobalGroups       = (Get-ADGroup -SearchBase $GroupsOu -Filter 'GroupScope -eq "Global"').Count
                DomainLocalGroups  = (Get-ADGroup -SearchBase $GroupsOu -Filter 'GroupScope -eq "DomainLocal"').Count
            }
        }

    Write-Host '[OK] Active Directory structure initialized.' -ForegroundColor Green
}
finally {
    $PlainPassword = $null
    $InitialPassword = $null
}
