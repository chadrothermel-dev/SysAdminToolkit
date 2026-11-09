function Get-VMwareSnapshotAudit {
    <#
    .SYNOPSIS
        Audits VMware vSphere Virtual Machine snapshots for age and size sprawl.
    .DESCRIPTION
        Queries vCenter via VMware.PowerCLI for all VM snapshots, flagging snapshots older than MinAgeDays or larger than MinSizeGB to prevent delta-disk latency and backup lockups.
    .PARAMETER ClusterName
        Optional vSphere Cluster name filter.
    .PARAMETER MinAgeDays
        Minimum age in days to return snapshots. Default is 3 (VMware best practice is <72 hours).
    .PARAMETER MinSizeGB
        Minimum snapshot size in GB to flag regardless of age. Default is 0 (returns all matching age threshold).
    .EXAMPLE
        PS C:\> Get-VMwareSnapshotAudit -MinAgeDays 3 -Verbose
        Returns all VMware VM snapshots older than 3 days across the connected vCenter Server.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$ClusterName,

        [Parameter()]
        [ValidateRange(0, 3650)]
        [int]$MinAgeDays = 3,

        [Parameter()]
        [ValidateRange(0, 102400)]
        [double]$MinSizeGB = 0
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
            $vms = if (-not [string]::IsNullOrWhiteSpace($ClusterName)) {
                Get-Cluster -Name $ClusterName -ErrorAction Stop | Get-VM -ErrorAction Stop
            }
            else {
                Get-VM -ErrorAction Stop
            }

            if ($null -eq $vms) { return }

            $snapshots = $vms | Get-Snapshot -ErrorAction Stop
            $now = Get-Date

            foreach ($snap in $snapshots) {
                $ageDays = [math]::Round(($now - $snap.Created).TotalDays, 1)
                $sizeGB  = [math]::Round($snap.SizeGB, 2)

                if ($ageDays -ge $MinAgeDays -or ($MinSizeGB -gt 0 -and $sizeGB -ge $MinSizeGB)) {
                    $severity = 'Normal'
                    if ($ageDays -ge 14 -or $sizeGB -ge 50) {
                        $severity = 'Critical'
                    }
                    elseif ($ageDays -ge 3 -or $sizeGB -ge 10) {
                        $severity = 'Warning'
                    }

                    [PSCustomObject]@{
                        VMName        = $snap.VM.Name
                        PowerState    = [string]$snap.VM.PowerState
                        SnapshotName  = $snap.Name
                        Description   = $snap.Description
                        CreatedTime   = $snap.Created
                        AgeDays       = $ageDays
                        SizeGB        = $sizeGB
                        IsQuiesced    = $snap.Quiesced
                        IncludesMemory = ($snap.PowerState -eq 'PoweredOn')
                        Severity      = $severity
                        SnapshotId    = $snap.Id
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to audit VMware snapshots: $_"
        }
    }
}
