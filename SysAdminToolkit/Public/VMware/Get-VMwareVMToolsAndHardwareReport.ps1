function Get-VMwareVMToolsAndHardwareReport {
    <#
    .SYNOPSIS
        Audits VMware Virtual Machines for VMware Tools status, VM Hardware Version, mounted ISOs, and CPU/RAM Limits.
    .DESCRIPTION
        Scans Virtual Machines in vSphere to identify out-of-date or stopped VMware Tools, outdated VM Hardware Versions, connected CD/DVD ISO drives (which block vMotion), and configured CPU/Memory Limits (which cause artificial CPU ready time or ballooning).
    .PARAMETER ClusterName
        Optional vSphere Cluster name filter.
    .PARAMETER OnlyWithFindings
        When specified, only outputs VMs that have at least one operational finding (outdated tools, mounted ISO, or CPU/RAM limits).
    .EXAMPLE
        PS C:\> Get-VMwareVMToolsAndHardwareReport -ClusterName "Prod-Cluster01" -OnlyWithFindings
        Returns all VMs in Prod-Cluster01 with outdated VMware Tools, mounted ISOs, or CPU/RAM limits.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$ClusterName,

        [Parameter()]
        [switch]$OnlyWithFindings
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

            foreach ($vm in $vms) {
                $toolsStatus = [string]$vm.ExtensionData.Guest.ToolsStatus
                $toolsVersion = [string]$vm.ExtensionData.Guest.ToolsVersion
                $hwVersion = [string]$vm.HardwareVersion

                $resConfig = $vm.ExtensionData.ResourceConfig
                $cpuLimitMhz = if ($null -ne $resConfig) { $resConfig.CpuAllocation.Limit } else { -1 }
                $memLimitMB  = if ($null -ne $resConfig) { $resConfig.MemoryAllocation.Limit } else { -1 }

                $cdDrives = @(Get-CDDrive -VM $vm -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionState.Connected -or $null -ne $_.IsoPath })
                $hasMountedIso = ($cdDrives.Count -gt 0)

                $findings = [System.Collections.Generic.List[string]]::new()
                if ($vm.PowerState -eq 'PoweredOn' -and $toolsStatus -in @('toolsOld', 'toolsNotInstalled', 'toolsNotRunning')) {
                    $findings.Add("VMTools:$toolsStatus")
                }
                if ($hasMountedIso) {
                    $findings.Add('MountedISO')
                }
                if ($cpuLimitMhz -ne -1 -and $null -ne $cpuLimitMhz) {
                    $findings.Add("CPULimit:${cpuLimitMhz}MHz")
                }
                if ($memLimitMB -ne -1 -and $null -ne $memLimitMB) {
                    $findings.Add("MemLimit:${memLimitMB}MB")
                }

                if ($OnlyWithFindings.IsPresent -and $findings.Count -eq 0) {
                    continue
                }

                [PSCustomObject]@{
                    VMName            = $vm.Name
                    PowerState        = [string]$vm.PowerState
                    VMHost            = if ($vm.VMHost) { $vm.VMHost.Name } else { 'Unknown' }
                    HardwareVersion   = $hwVersion
                    ToolsStatus       = $toolsStatus
                    ToolsVersion      = $toolsVersion
                    MountedIsoConnected = $hasMountedIso
                    CPULimitMHz       = if ($cpuLimitMhz -eq -1) { 'Unlimited' } else { [string]$cpuLimitMhz }
                    MemoryLimitMB     = if ($memLimitMB -eq -1) { 'Unlimited' } else { [string]$memLimitMB }
                    Findings          = ($findings -join ', ')
                    Timestamp         = Get-Date -Format 'o'
                }
            }
        }
        catch {
            Write-Error -Message "Failed to generate VMware Tools and Hardware Report: $_"
        }
    }
}
