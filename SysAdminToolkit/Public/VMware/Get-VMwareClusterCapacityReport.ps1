function Get-VMwareClusterCapacityReport {
    <#
    .SYNOPSIS
        Reports VMware vSphere Cluster CPU, Memory, vCPU-to-pCore oversubscription, and Datastore capacity.
    .DESCRIPTION
        Calculates cluster-level health and capacity metrics including ESXi host states, HA/DRS configuration, vCPU:pCore ratio, memory allocation vs usage, and lowest free datastore percentage.
    .PARAMETER ClusterName
        Optional vSphere Cluster name(s) to query. Defaults to all clusters.
    .EXAMPLE
        PS C:\> Get-VMwareClusterCapacityReport -Verbose
        Outputs capacity and oversubscription ratios for every vSphere cluster in vCenter.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$ClusterName
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
            $clusters = if ($PSBoundParameters.ContainsKey('ClusterName') -and $ClusterName.Count -gt 0) {
                Get-Cluster -Name $ClusterName -ErrorAction Stop
            }
            else {
                Get-Cluster -ErrorAction Stop
            }

            foreach ($cluster in $clusters) {
                $vmHosts    = @(Get-VMHost -Location $cluster -ErrorAction Stop)
                $connected  = @($vmHosts | Where-Object { $_.ConnectionState -eq 'Connected' })
                $maintHosts = @($vmHosts | Where-Object { $_.ConnectionState -eq 'Maintenance' })
                $vms        = @(Get-VM -Location $cluster -ErrorAction Stop)
                $poweredOn  = @($vms | Where-Object { $_.PowerState -eq 'PoweredOn' })
                $datastores = @(Get-Datastore -RelatedObject $cluster -ErrorAction SilentlyContinue)

                $totalPCores = ($connected | Measure-Object -Property NumCpu -Sum).Sum
                $totalVCPUs  = ($poweredOn | Measure-Object -Property NumCpu -Sum).Sum
                $vCpuRatio   = if ($totalPCores -gt 0) { [math]::Round($totalVCPUs / $totalPCores, 2) } else { 0 }

                $totalMemGB = [math]::Round(($connected | Measure-Object -Property MemoryTotalGB -Sum).Sum, 1)
                $usedMemGB  = [math]::Round(($connected | Measure-Object -Property MemoryUsageGB -Sum).Sum, 1)
                $allocMemGB = [math]::Round(($poweredOn | Measure-Object -Property MemoryGB -Sum).Sum, 1)
                $memUsedPct = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB) * 100, 1) } else { 0 }

                $lowestDsNote = 'None'
                if ($datastores.Count -gt 0) {
                    $lowestDs = $datastores |
                        Where-Object { $_.CapacityGB -gt 0 } |
                        Select-Object -Property Name, @{N = 'FreePct'; E = { [math]::Round(($_.FreeSpaceGB / $_.CapacityGB) * 100, 1) } }, FreeSpaceGB |
                        Sort-Object -Property FreePct |
                        Select-Object -First 1
                    if ($null -ne $lowestDs) {
                        $lowestDsNote = "$($lowestDs.Name) ($($lowestDs.FreePct)% / $([math]::Round($lowestDs.FreeSpaceGB, 1)) GB free)"
                    }
                }

                [PSCustomObject]@{
                    ClusterName          = $cluster.Name
                    HAEnabled            = $cluster.HAEnabled
                    DRSEnabled           = $cluster.DrsEnabled
                    DRSAutomationLevel   = [string]$cluster.DrsAutomationLevel
                    TotalHosts           = $vmHosts.Count
                    ConnectedHosts       = $connected.Count
                    MaintenanceHosts     = $maintHosts.Count
                    PoweredOnVMs         = $poweredOn.Count
                    TotalVMs             = $vms.Count
                    TotalPhysicalCores   = $totalPCores
                    AllocatedvCPUs       = $totalVCPUs
                    vCPUToPCoreRatio     = "${vCpuRatio}:1"
                    MemoryTotalGB        = $totalMemGB
                    MemoryUsedGB         = $usedMemGB
                    MemoryUsedPercent    = $memUsedPct
                    MemoryAllocatedGB    = $allocMemGB
                    LowestFreeDatastore  = $lowestDsNote
                    Timestamp            = Get-Date -Format 'o'
                }
            }
        }
        catch {
            Write-Error -Message "Failed to generate VMware Cluster Capacity Report: $_"
        }
    }
}
