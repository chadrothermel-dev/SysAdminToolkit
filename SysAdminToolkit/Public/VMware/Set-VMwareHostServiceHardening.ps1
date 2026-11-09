function Set-VMwareHostServiceHardening {
    <#
    .SYNOPSIS
        Starts, stops, and configures startup policy for ESXi host services (SSH, ESXi Shell, NTP) across hosts or clusters.
    .DESCRIPTION
        Enables or disables ESXi host services such as TSM-SSH (SSH), TSM (ESXi Shell), or ntpd (NTP daemon) and sets their startup policy (off, on, automatic) to comply with VMware Security Configuration Guide hardening standards or open temporary troubleshooting access.
    .PARAMETER VMHostName
        One or more ESXi hostnames.
    .PARAMETER ClusterName
        Optional vSphere Cluster name to target all hosts in the cluster.
    .PARAMETER ServiceKey
        Target ESXi service key:
        - TSM-SSH (SSH Server)
        - TSM (ESXi Shell)
        - ntpd (NTP Daemon)
        - DCUI (Direct Console UI)
    .PARAMETER State
        Desired runtime state: Start or Stop.
    .PARAMETER StartupPolicy
        Desired host service startup policy: off, on, or automatic.
    .EXAMPLE
        PS C:\> Set-VMwareHostServiceHardening -ClusterName "Prod-Cluster01" -ServiceKey "TSM-SSH" -State Stop -StartupPolicy off -WhatIf
        Previews stopping SSH and setting its startup policy to 'off' across all ESXi hosts in Prod-Cluster01.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$VMHostName,

        [Parameter()]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('TSM-SSH', 'TSM', 'ntpd', 'DCUI')]
        [string]$ServiceKey,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Start', 'Stop')]
        [string]$State,

        [Parameter()]
        [ValidateSet('off', 'on', 'automatic')]
        [string]$StartupPolicy
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
            $targetHosts = if (-not [string]::IsNullOrWhiteSpace($ClusterName)) {
                Get-Cluster -Name $ClusterName -ErrorAction Stop | Get-VMHost -ErrorAction Stop
            }
            elseif ($PSBoundParameters.ContainsKey('VMHostName') -and $VMHostName.Count -gt 0) {
                Get-VMHost -Name $VMHostName -ErrorAction Stop
            }
            else {
                throw [System.ArgumentException]::new("Specify either -VMHostName or -ClusterName.")
            }

            foreach ($vmHost in $targetHosts) {
                $svc = Get-VMHostService -VMHost $vmHost -ErrorAction Stop | Where-Object { $_.Key -eq $ServiceKey } | Select-Object -First 1
                if ($null -eq $svc) {
                    Write-Warning "Service '$ServiceKey' not found on ESXi host '$($vmHost.Name)'."
                    continue
                }

                $actionLabel = "$State service '$ServiceKey'" + $(if ($StartupPolicy) { " and set StartupPolicy to '$StartupPolicy'" } else { '' })
                if ($PSCmdlet.ShouldProcess("ESXi Host '$($vmHost.Name)'", $actionLabel)) {
                    if (-not [string]::IsNullOrWhiteSpace($StartupPolicy)) {
                        $svc = Set-VMHostService -HostService $svc -Policy $StartupPolicy -Confirm:$false -ErrorAction Stop
                    }

                    if ($State -eq 'Start' -and -not $svc.Running) {
                        $svc = Start-VMHostService -HostService $svc -Confirm:$false -ErrorAction Stop
                    }
                    elseif ($State -eq 'Stop' -and $svc.Running) {
                        $svc = Stop-VMHostService -HostService $svc -Confirm:$false -ErrorAction Stop
                    }

                    [PSCustomObject]@{
                        VMHostName    = $vmHost.Name
                        ServiceKey    = $svc.Key
                        ServiceLabel  = $svc.Label
                        Running       = $svc.Running
                        StartupPolicy = $svc.Policy
                        Timestamp     = Get-Date -Format 'o'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to update ESXi service '$ServiceKey': $_"
        }
    }
}
