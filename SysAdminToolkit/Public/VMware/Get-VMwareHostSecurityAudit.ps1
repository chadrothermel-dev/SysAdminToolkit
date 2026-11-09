function Get-VMwareHostSecurityAudit {
    <#
    .SYNOPSIS
        Audits VMware ESXi hosts for Lockdown Mode, Exception Users, SSH/ESXi Shell status, NTP, and Syslog hardening.
    .DESCRIPTION
        Inspects ESXi hosts across vCenter or a specific cluster to verify security posture: Lockdown Mode (Disabled/Normal/Strict), Lockdown Exception Users, SSH (TSM-SSH) running state and startup policy, ESXi Shell (TSM) running state, NTP (ntpd) daemon state and servers, and remote Syslog configuration.
    .PARAMETER ClusterName
        Optional vSphere Cluster name filter.
    .PARAMETER VMHostName
        Optional ESXi host name filter.
    .EXAMPLE
        PS C:\> Get-VMwareHostSecurityAudit -ClusterName "Prod-Cluster01"
        Returns the security and hardening posture of all ESXi hosts in Prod-Cluster01.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$ClusterName,

        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$VMHostName
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName 'VMware.PowerCLI'
        if ($null -eq $Global:DefaultVIServers -or $Global:DefaultVIServers.Count -eq 0) {
            throw [System.InvalidOperationException]::new("No active vCenter connection found. Run Connect-VIServer first.")
        }
    }

    process {
        try {
            $vmHosts = if (-not [string]::IsNullOrWhiteSpace($ClusterName)) {
                Get-Cluster -Name $ClusterName -ErrorAction Stop | Get-VMHost -ErrorAction Stop
            }
            elseif ($PSBoundParameters.ContainsKey('VMHostName') -and $VMHostName.Count -gt 0) {
                Get-VMHost -Name $VMHostName -ErrorAction Stop
            }
            else {
                Get-VMHost -ErrorAction Stop
            }

            foreach ($vmHost in $vmHosts) {
                $lockdownMode = 'Unknown'
                $exceptionUsers = ''
                if ($null -ne $vmHost.ExtensionData.ConfigManager.HostAccessManager) {
                    $accessMgr = Get-View -Id $vmHost.ExtensionData.ConfigManager.HostAccessManager -ErrorAction SilentlyContinue
                    if ($null -ne $accessMgr) {
                        $lockdownMode = [string]$accessMgr.LockdownMode
                        $exceptionUsers = ($accessMgr.QueryLockdownExceptions() -join ', ')
                    }
                }

                $services = Get-VMHostService -VMHost $vmHost -ErrorAction SilentlyContinue
                $sshSvc   = $services | Where-Object { $_.Key -eq 'TSM-SSH' } | Select-Object -First 1
                $shellSvc = $services | Where-Object { $_.Key -eq 'TSM' } | Select-Object -First 1
                $ntpSvc   = $services | Where-Object { $_.Key -eq 'ntpd' } | Select-Object -First 1

                $ntpServers = @(Get-VMHostNtpServer -VMHost $vmHost -ErrorAction SilentlyContinue)
                $syslogAdv  = Get-AdvancedSetting -Entity $vmHost -Name 'Syslog.global.logHost' -ErrorAction SilentlyContinue

                $findings = [System.Collections.Generic.List[string]]::new()
                if ($lockdownMode -eq 'lockdownDisabled') { $findings.Add('LockdownDisabled') }
                if ($null -ne $sshSvc -and $sshSvc.Running) { $findings.Add('SSHRunning') }
                if ($null -ne $shellSvc -and $shellSvc.Running) { $findings.Add('ESXiShellRunning') }
                if ($null -eq $ntpSvc -or -not $ntpSvc.Running -or $ntpServers.Count -eq 0) { $findings.Add('NTPNotConfiguredOrStopped') }
                if ($null -eq $syslogAdv -or [string]::IsNullOrWhiteSpace([string]$syslogAdv.Value)) { $findings.Add('NoRemoteSyslog') }

                [PSCustomObject]@{
                    VMHostName           = $vmHost.Name
                    ClusterName          = if ($vmHost.Parent) { $vmHost.Parent.Name } else { 'Standalone' }
                    ESXiVersion          = "$($vmHost.Version) (Build $($vmHost.Build))"
                    LockdownMode         = $lockdownMode
                    ExceptionUsers       = $exceptionUsers
                    SSHRunning           = if ($null -ne $sshSvc) { $sshSvc.Running } else { $false }
                    SSHPolicy            = if ($null -ne $sshSvc) { $sshSvc.Policy } else { 'Unknown' }
                    ESXiShellRunning     = if ($null -ne $shellSvc) { $shellSvc.Running } else { $false }
                    ESXiShellPolicy      = if ($null -ne $shellSvc) { $shellSvc.Policy } else { 'Unknown' }
                    NTPRunning           = if ($null -ne $ntpSvc) { $ntpSvc.Running } else { $false }
                    NTPServers           = ($ntpServers -join ', ')
                    RemoteSyslogHost     = if ($null -ne $syslogAdv) { [string]$syslogAdv.Value } else { '' }
                    ComplianceStatus     = if ($findings.Count -eq 0) { 'Compliant' } else { 'FindingsDetected' }
                    SecurityFindings     = ($findings -join ', ')
                    Timestamp            = Get-Date -Format 'o'
                }
            }
        }
        catch {
            Write-Error -Message "Failed to audit VMware ESXi host security: $_"
        }
    }
}
