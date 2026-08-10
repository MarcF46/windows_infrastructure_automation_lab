@{
    LabName              = 'WindowsInfraLab'
    DomainName           = 'corp.example'
    DomainAdminUser      = 'LabAdmin'

    LabSourcesPath       = 'D:\LabSources'
    IsoDirectory         = 'D:\LabSources\ISOs'
    VmRootPath           = 'C:\AutomatedLab-VMs'
    ServerIsoPath        = 'D:\LabSources\ISOs\windows_server_2022_eval.iso'
    ClientIsoPath        = 'D:\LabSources\ISOs\windows_11_enterprise_eval.iso'

    ServerOsName         = 'Windows Server 2022 Standard Evaluation'
    ClientOsName         = 'Windows 11 Enterprise Evaluation'

    NetworkName          = 'WindowsInfraLab'
    AddressSpace         = '192.168.50.0/24'
    SubnetMask           = '255.255.255.0'
    HostGateway          = '192.168.50.1'

    DomainControllerName = 'DC01'
    DomainControllerIp   = '192.168.50.10'
    FileServerName       = 'SRV01'
    FileServerIp         = '192.168.50.20'
    ClientName           = 'CL01'
    ClientIp             = '192.168.50.30'

    DhcpScopeId          = '192.168.50.0'
    DhcpStartRange       = '192.168.50.100'
    DhcpEndRange         = '192.168.50.199'
    DhcpScopeName        = 'Lab-Clients'

    DataRoot             = 'C:\LabData'

    Departments = @(
        @{ Key = 'Finance';    DisplayName = 'Finance' }
        @{ Key = 'HR';         DisplayName = 'Human Resources' }
        @{ Key = 'IT';         DisplayName = 'IT' }
        @{ Key = 'Operations'; DisplayName = 'Operations' }
        @{ Key = 'Sales';      DisplayName = 'Sales' }
    )
}
