function Remove-VMwareStaleSnapshot {
    <#
    .SYNOPSIS
        Safely removes stale VMware vSphere VM snapshots older than a specified age threshold.
    .DESCRIPTION
        Finds and deletes VMware VM snapshots older than MinAgeDays, excluding backup appliance temporary snapshots (such as Veeam or Commvault active jobs) unless overridden, with ShouldProcess safety controls.
    .PARAMETER VMName
        Optional VM name filter. Accepts wildcard patterns or pipeline input from Get-VMwareSnapshotAudit.
    .PARAMETER MinAgeDays
        Minimum snapshot age in days eligible for removal. Default is 7.
    .PARAMETER ExcludeSnapshotPattern
        Regex pattern of snapshot names to skip (protects active backup/replication snapshots by default).
    .PARAMETER RunAsync
        Submits snapshot deletion tasks asynchronously in vCenter.
    .EXAMPLE
        PS C:\> Remove-VMwareStaleSnapshot -MinAgeDays 7 -WhatIf
        Previews removing all VM snapshots older than 7 days while skipping active backup snapshots.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$VMName = @('*'),

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$MinAgeDays = 7,

        [Parameter()]
        [string]$ExcludeSnapshotPattern = '(?i)(VEEAM|Veritas|Commvault|Zerto|Rubrik|Cohesity|DoNotDelete)',

        [Parameter()]
        [switch]$RunAsync
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName 'VMware.PowerCLI'
        if ($null -eq $Global:DefaultVIServers -or $Global:DefaultVIServers.Count -eq 0) {
            throw [System.InvalidOperationException]::new("No active vCenter connection found. Run Connect-VIServer first.")
        }
        $cutoffDate = (Get-Date).AddDays(-$MinAgeDays)
    }

    process {
        foreach ($name in $VMName) {
            try {
                $vms = Get-VM -Name $name -ErrorAction Stop
                foreach ($vm in $vms) {
                    $snapshots = Get-Snapshot -VM $vm -ErrorAction Stop | Where-Object { $_.Created -lt $cutoffDate }
                    foreach ($snap in $snapshots) {
                        if (-not [string]::IsNullOrWhiteSpace($ExcludeSnapshotPattern) -and ($snap.Name -match $ExcludeSnapshotPattern -or $snap.Description -match $ExcludeSnapshotPattern)) {
                            Write-Warning "Skipping snapshot '$($snap.Name)' on VM '$($vm.Name)' because it matches ExclusionPattern."
                            continue
                        }

                        $ageDays = [math]::Round(((Get-Date) - $snap.Created).TotalDays, 1)
                        $sizeGB  = [math]::Round($snap.SizeGB, 2)
                        $targetLabel = "VM '$($vm.Name)' -> Snapshot '$($snap.Name)' (Age: $ageDays days, Size: $sizeGB GB)"

                        if ($PSCmdlet.ShouldProcess($targetLabel, 'Remove-Snapshot and Consolidate Disks')) {
                            $removeParams = @{
                                Snapshot    = $snap
                                Confirm     = $false
                                ErrorAction = 'Stop'
                            }
                            if ($RunAsync.IsPresent) {
                                $removeParams['RunAsync'] = $true
                            }

                            $null = Remove-Snapshot @removeParams

                            [PSCustomObject]@{
                                VMName        = $vm.Name
                                SnapshotName  = $snap.Name
                                AgeDays       = $ageDays
                                ReclaimedGB   = $sizeGB
                                ExecutionMode = if ($RunAsync.IsPresent) { 'Async' } else { 'Synchronous' }
                                Status        = 'Removed'
                                Timestamp     = Get-Date -Format 'o'
                            }
                        }
                    }
                }
            }
            catch {
                Write-Error -Message "Failed removing stale snapshots for VM filter '$name': $_" -TargetObject $name
            }
        }
    }
}
