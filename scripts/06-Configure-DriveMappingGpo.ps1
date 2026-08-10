#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Creates Group Policy Preferences drive mappings for the lab users.

.DESCRIPTION
    Creates or updates a dedicated GPO, writes the Drive Maps preference XML
    into SYSVOL and applies item-level targeting based on global department
    groups. SMB and NTFS permissions remain the actual access-control boundary.
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

$DriveDefinitions = @(
    @{ Letter='G'; Share='General';    Label='General data';          Group='GG_All_Employees';      Uid='{0B64F65B-47DF-4B7D-8A62-58A7A045D851}' }
    @{ Letter='F'; Share='Finance';    Label='Finance data';          Group='GG_Finance_Employees';  Uid='{DDC6EBAB-8BD6-4B3B-BF80-9E4F3F7FC1F1}' }
    @{ Letter='H'; Share='HR';         Label='Human Resources data';  Group='GG_HR_Employees';       Uid='{1D327895-B02D-4B01-A11E-FA55B9CB625A}' }
    @{ Letter='I'; Share='IT';         Label='IT data';               Group='GG_IT_Employees';       Uid='{C45F952C-7081-4B4D-8E30-F4EB0F4ED827}' }
    @{ Letter='O'; Share='Operations'; Label='Operations data';       Group='GG_Operations_Employees';Uid='{ACD01C4A-B5D5-477E-8D55-FD3CEB1CA9AB}' }
    @{ Letter='S'; Share='Sales';      Label='Sales data';            Group='GG_Sales_Employees';    Uid='{B247FC01-6F9B-4FD1-9B05-8636082F0EED}' }
)

$DriveDefinitionsJson = $DriveDefinitions | ConvertTo-Json -Depth 5 -Compress

Invoke-LabCommand `
    -ComputerName $Config.DomainControllerName `
    -ActivityName 'Configure Group Policy drive mappings' `
    -ArgumentList $Config.DomainName, $Config.FileServerName, $DriveDefinitionsJson `
    -ScriptBlock {
        param(
            [string]$DomainName,
            [string]$FileServerName,
            [string]$DriveDefinitionsJson
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        Import-Module ActiveDirectory -ErrorAction Stop
        if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
            Install-WindowsFeature -Name GPMC -IncludeManagementTools | Out-Null
        }
        Import-Module GroupPolicy -ErrorAction Stop

        $Domain = Get-ADDomain -ErrorAction Stop
        if ($Domain.DNSRoot -ne $DomainName) {
            throw "Unexpected domain: $($Domain.DNSRoot)"
        }

        $UserOuDn = "OU=Users,OU=Company,$($Domain.DistinguishedName)"
        Get-ADOrganizationalUnit -Identity $UserOuDn -ErrorAction Stop | Out-Null

        $GpoName = 'Lab - Drive Mappings'
        $GpoComment = 'Managed by the Windows Infrastructure Automation Lab.'
        $DriveMapsClientSideExtension = '{5794DAFD-BE60-433f-88A2-1A31939AC01F}'
        $DriveMapsToolExtension = '{2EA1A81B-48E5-45E9-8BB7-A6E3AC170006}'
        $DriveMapsExtensionToken = "[$DriveMapsClientSideExtension$DriveMapsToolExtension]"
        $DriveDefinitions = @($DriveDefinitionsJson | ConvertFrom-Json)

        $ResolvedDrives = foreach ($Drive in $DriveDefinitions) {
            $Group = Get-ADGroup -Identity $Drive.Group -Properties SID, GroupScope, GroupCategory -ErrorAction Stop
            if ($Group.GroupScope -ne 'Global' -or $Group.GroupCategory -ne 'Security') {
                throw "Drive target '$($Drive.Group)' must be a global security group."
            }

            $SharePath = "\\$FileServerName\$($Drive.Share)"
            if (-not (Test-Path -LiteralPath $SharePath)) {
                throw "Share is not reachable from the domain controller: $SharePath"
            }

            [pscustomobject]@{
                Letter     = $Drive.Letter
                Label      = $Drive.Label
                Path       = $SharePath
                FilterName = "$($Domain.NetBIOSName)\$($Group.Name)"
                FilterSid  = $Group.SID.Value
                Uid        = $Drive.Uid
            }
        }

        $Gpo = Get-GPO -Name $GpoName -Domain $DomainName -ErrorAction SilentlyContinue
        if (-not $Gpo) {
            $Gpo = New-GPO -Name $GpoName -Comment $GpoComment -Domain $DomainName
        }
        elseif ($Gpo.Description -ne $GpoComment) {
            throw "A GPO named '$GpoName' exists but is not managed by this lab."
        }

        $ExistingLink = (Get-GPInheritance -Target $UserOuDn).GpoLinks |
            Where-Object DisplayName -eq $GpoName
        if (-not $ExistingLink) {
            New-GPLink -Name $GpoName -Target $UserOuDn -LinkEnabled Yes | Out-Null
        }

        $GpoGuid = '{' + $Gpo.Id.ToString().ToUpperInvariant() + '}'
        $GpoAdPath = "CN=$GpoGuid,CN=Policies,CN=System,$($Domain.DistinguishedName)"
        $GpoAdObject = Get-ADObject `
            -Identity $GpoAdPath `
            -Properties gPCFileSysPath, gPCUserExtensionNames, versionNumber `
            -ErrorAction Stop

        $GptRoot = [string]$GpoAdObject.gPCFileSysPath
        $DrivesDirectory = Join-Path $GptRoot 'User\Preferences\Drives'
        $DrivesXmlPath = Join-Path $DrivesDirectory 'Drives.xml'
        $GptIniPath = Join-Path $GptRoot 'GPT.ini'

        $Xml = [System.Xml.XmlDocument]::new()
        [void]$Xml.AppendChild($Xml.CreateXmlDeclaration('1.0', 'utf-8', $null))
        $DrivesNode = $Xml.CreateElement('Drives')
        [void]$DrivesNode.SetAttribute('clsid', '{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}')
        [void]$DrivesNode.SetAttribute('disabled', '0')
        [void]$Xml.AppendChild($DrivesNode)

        foreach ($Drive in $ResolvedDrives) {
            $DriveNode = $Xml.CreateElement('Drive')
            [void]$DriveNode.SetAttribute('clsid', '{935D1B74-9CB8-4e3c-9914-7DD559B7A417}')
            [void]$DriveNode.SetAttribute('name', "$($Drive.Letter):")
            [void]$DriveNode.SetAttribute('status', "$($Drive.Letter):")
            [void]$DriveNode.SetAttribute('image', '1')
            [void]$DriveNode.SetAttribute('changed', '2026-08-10 00:00:00')
            [void]$DriveNode.SetAttribute('uid', $Drive.Uid)
            [void]$DriveNode.SetAttribute('desc', "Lab mapping: $($Drive.Label)")
            [void]$DriveNode.SetAttribute('bypassErrors', '1')
            [void]$DriveNode.SetAttribute('removePolicy', '1')

            $Properties = $Xml.CreateElement('Properties')
            [void]$Properties.SetAttribute('action', 'R')
            [void]$Properties.SetAttribute('thisDrive', 'NOCHANGE')
            [void]$Properties.SetAttribute('allDrives', 'NOCHANGE')
            [void]$Properties.SetAttribute('userName', '')
            [void]$Properties.SetAttribute('path', $Drive.Path)
            [void]$Properties.SetAttribute('label', $Drive.Label)
            [void]$Properties.SetAttribute('persistent', '1')
            [void]$Properties.SetAttribute('useLetter', '1')
            [void]$Properties.SetAttribute('letter', $Drive.Letter)
            [void]$DriveNode.AppendChild($Properties)

            $Filters = $Xml.CreateElement('Filters')
            $FilterGroup = $Xml.CreateElement('FilterGroup')
            [void]$FilterGroup.SetAttribute('bool', 'AND')
            [void]$FilterGroup.SetAttribute('not', '0')
            [void]$FilterGroup.SetAttribute('name', $Drive.FilterName)
            [void]$FilterGroup.SetAttribute('sid', $Drive.FilterSid)
            [void]$FilterGroup.SetAttribute('userContext', '1')
            [void]$FilterGroup.SetAttribute('primaryGroup', '0')
            [void]$FilterGroup.SetAttribute('localGroup', '0')
            [void]$Filters.AppendChild($FilterGroup)
            [void]$DriveNode.AppendChild($Filters)
            [void]$DrivesNode.AppendChild($DriveNode)
        }

        if (-not (Test-Path -LiteralPath $DrivesDirectory)) {
            New-Item -Path $DrivesDirectory -ItemType Directory -Force | Out-Null
        }

        $WriterSettings = [System.Xml.XmlWriterSettings]::new()
        $WriterSettings.Encoding = [System.Text.UTF8Encoding]::new($true)
        $WriterSettings.Indent = $true
        $Writer = [System.Xml.XmlWriter]::Create($DrivesXmlPath, $WriterSettings)
        try {
            $Xml.Save($Writer)
        }
        finally {
            $Writer.Dispose()
        }

        $GptIni = Get-Content -LiteralPath $GptIniPath -Raw
        $VersionMatch = [regex]::Match($GptIni, '(?im)^Version\s*=\s*(\d+)\s*$')
        if (-not $VersionMatch.Success) {
            throw 'GPT.ini does not contain a valid version number.'
        }

        $OldVersion = [int]$VersionMatch.Groups[1].Value
        $ComputerVersion = ($OldVersion -shr 16) -band 0xFFFF
        $UserVersion = $OldVersion -band 0xFFFF
        $NewVersion = ($ComputerVersion -shl 16) -bor (($UserVersion + 1) -band 0xFFFF)
        $UpdatedGptIni = [regex]::Replace($GptIni, '(?im)^Version\s*=\s*\d+\s*$', "Version=$NewVersion")
        [System.IO.File]::WriteAllText($GptIniPath, $UpdatedGptIni, [System.Text.Encoding]::ASCII)

        $ExtensionGroups = [System.Collections.Generic.List[string]]::new()
        $CurrentExtensions = [string]$GpoAdObject.gPCUserExtensionNames
        if (-not [string]::IsNullOrWhiteSpace($CurrentExtensions)) {
            foreach ($Match in [regex]::Matches($CurrentExtensions, '\[[^\]]+\]')) {
                $ExtensionGroups.Add($Match.Value)
            }
        }
        if (-not $ExtensionGroups.Contains($DriveMapsExtensionToken)) {
            $ExtensionGroups.Add($DriveMapsExtensionToken)
        }

        Set-ADObject `
            -Identity $GpoAdPath `
            -Replace @{
                gPCUserExtensionNames = (@($ExtensionGroups | Sort-Object -Unique) -join '')
                versionNumber = $NewVersion
            }

        [pscustomobject]@{
            Gpo          = $GpoName
            TargetOu     = $UserOuDn
            DriveCount   = $ResolvedDrives.Count
            SysvolFile   = $DrivesXmlPath
            PolicyVersion= $NewVersion
        }
    }

Write-Host '[OK] Group Policy drive mappings configured.' -ForegroundColor Green
