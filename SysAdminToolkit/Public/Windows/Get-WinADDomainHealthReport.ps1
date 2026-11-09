function Get-WinADDomainHealthReport {
    <#
    .SYNOPSIS
        Audits Active Directory Domain Controllers for FSMO roles, replication failures, and core AD services.
    .DESCRIPTION
        Queries Active Directory for Forest and Domain FSMO role holders, enumerates all Domain Controllers, checks for inbound AD replication failures (Get-ADReplicationFailure), and verifies critical DC services (NTDS, DNS, Netlogon, Kdc, DFSR, W32Time).
    .PARAMETER Server
        Optional Domain FQDN or Domain Controller hostname to query.
    .EXAMPLE
        PS C:\> Get-WinADDomainHealthReport -Verbose
        Returns health, FSMO roles held, replication failure count, and core service status for every Domain Controller.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Server
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName 'ActiveDirectory'
        $coreDcServices = @('NTDS', 'DNS', 'Netlogon', 'Kdc', 'DFSR', 'W32Time')
    }

    process {
        try {
            $adParams = @{ ErrorAction = 'Stop' }
            if (-not [string]::IsNullOrWhiteSpace($Server)) {
                $adParams['Server'] = $Server
            }

            $forest = Get-ADForest @adParams
            $domain = Get-ADDomain @adParams
            $dcs    = @(Get-ADDomainController -Filter * @adParams)

            foreach ($dc in $dcs) {
                $rolesHeld = [System.Collections.Generic.List[string]]::new()
                if ($forest.SchemaMaster -eq $dc.HostName)       { $rolesHeld.Add('SchemaMaster') }
                if ($forest.DomainNamingMaster -eq $dc.HostName) { $rolesHeld.Add('DomainNamingMaster') }
                if ($domain.PDCEmulator -eq $dc.HostName)        { $rolesHeld.Add('PDCEmulator') }
                if ($domain.RIDMaster -eq $dc.HostName)          { $rolesHeld.Add('RIDMaster') }
                if ($domain.InfrastructureMaster -eq $dc.HostName) { $rolesHeld.Add('InfrastructureMaster') }

                $repFailures = @()
                try {
                    $repFailures = @(Get-ADReplicationFailure -Target $dc.HostName -ErrorAction Stop)
                }
                catch {
                    Write-Verbose "Could not query replication failures on $($dc.HostName): $_"
                }

                $stoppedDcSvcs = @()
                try {
                    $svcs = Get-CimInstance -ComputerName $dc.HostName -ClassName Win32_Service -ErrorAction Stop |
                        Where-Object { $coreDcServices -contains $_.Name -and $_.State -ne 'Running' }
                    $stoppedDcSvcs = @($svcs | Select-Object -ExpandProperty Name)
                }
                catch {
                    $stoppedDcSvcs = @('CIMUnreachable')
                }

                $health = if ($repFailures.Count -eq 0 -and $stoppedDcSvcs.Count -eq 0) { 'Healthy' } else { 'Warning' }

                [PSCustomObject]@{
                    DCName               = $dc.Name
                    HostName             = $dc.HostName
                    Site                 = $dc.Site
                    IPv4Address          = $dc.IPv4Address
                    OperatingSystem      = $dc.OperatingSystem
                    IsGlobalCatalog      = $dc.IsGlobalCatalog
                    IsReadOnly           = $dc.IsReadOnly
                    FSMORoles            = if ($rolesHeld.Count -gt 0) { ($rolesHeld -join ', ') } else { 'None' }
                    ReplicationFailures  = $repFailures.Count
                    StoppedCoreServices  = ($stoppedDcSvcs -join ', ')
                    HealthStatus         = $health
                    Timestamp            = Get-Date -Format 'o'
                }
            }
        }
        catch {
            Write-Error -Message "Failed to generate Active Directory Domain Health Report: $_"
        }
    }
}
