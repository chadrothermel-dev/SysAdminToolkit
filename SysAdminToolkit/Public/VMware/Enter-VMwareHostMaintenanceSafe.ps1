function Enter-VMwareHostMaintenanceSafe {
    <#
    .SYNOPSIS
        Performs pre-flight evacuation checks and safely places a VMware ESXi host into Maintenance Mode.
    .DESCRIPTION
        Verifies whether any VMs on the target ESXi host have connected CD/DVD ISO drives (which block vMotion), checks cluster DRS status, optionally disconnects mounted ISOs, and places the ESXi host into Maintenance Mode with vSAN data migration support.
    .PARAMETER VMHostName
        Hostname or FQDN of the ESXi host to place into Maintenance Mode.
    .PARAMETER DisconnectMountedIso
        Automatically disconnects mounted CD/DVD drives on VMs residing on the host prior to evacuation.
    .PARAMETER VsanDataMigrationMode
        vSAN data evacuation mode: EnsureAccessibility, Full, or NoDataMigration. Default is EnsureAccessibility.
    .PARAMETER EvacuatePoweredOffVMs
        Evacuates powered-off VMs and templates to other hosts in the cluster.
    .EXAMPLE
        PS C:\> Enter-VMwareHostMaintenanceSafe -VMHostName "esxi01.corp.local" -DisconnectMountedIso -WhatIf
        Runs pre-flight vMotion blocker checks and previews placing esxi01.corp.local into Maintenance Mode.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VMHostName,

        [Parameter()]
        [switch]$DisconnectMountedIso,

        [Parameter()]
        [ValidateSet('EnsureAccessibility', 'Full', 'NoDataMigration')]
        [string]$VsanDataMigrationMode = 'EnsureAccessibility',

        [Parameter()]
        [switch]$EvacuatePoweredOffVMs
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
            $vmHost = Get-VMHost -Name $VMHostName -ErrorAction Stop
            $cluster = Get-Cluster -VMHost $vmHost -ErrorAction SilentlyContinue
            $hostVMs = @(Get-VM -Location $vmHost -ErrorAction Stop)

            # Check for connected CD drives that could block vMotion
            $vmsWithCd = @()
            foreach ($vm in $hostVMs) {
                $cdDrives = Get-CDDrive -VM $vm -ErrorAction SilentlyContinue |
                    Where-Object { $_.ConnectionState.Connected -or $null -ne $_.IsoPath }
                if ($cdDrives) {
                    $vmsWithCd += $vm.Name
                    if ($DisconnectMountedIso.IsPresent -and $PSCmdlet.ShouldProcess("VM '$($vm.Name)' on '$VMHostName'", "Disconnect mounted CD/DVD ISO drive")) {
                        $null = $cdDrives | Set-CDDrive -NoMedia -Connected:$false -Confirm:$false -ErrorAction Stop
                    }
                }
            }

            if ($vmsWithCd.Count -gt 0 -and -not $DisconnectMountedIso.IsPresent) {
                Write-Warning "Host '$VMHostName' has VMs with mounted CD/ISO drives that may block vMotion: $($vmsWithCd -join ', '). Re-run with -DisconnectMountedIso to clear them automatically."
            }

            $actionLabel = "Enter Maintenance Mode (EvacuatePoweredOffVMs: $($EvacuatePoweredOffVMs.IsPresent), vSAN Mode: $VsanDataMigrationMode)"
            if ($PSCmdlet.ShouldProcess("ESXi Host '$VMHostName' (Current VMs: $($hostVMs.Count))", $actionLabel)) {
                $maintParams = @{
                    VMHost                    = $vmHost
                    State                     = 'Maintenance'
                    VsanDataMigrationMode     = $VsanDataMigrationMode
                    EvacuatePoweredOffVms     = $EvacuatePoweredOffVMs.IsPresent
                    Confirm                   = $false
                    ErrorAction               = 'Stop'
                }

                $updatedHost = Set-VMHost @maintParams

                [PSCustomObject]@{
                    VMHostName            = $updatedHost.Name
                    ClusterName           = if ($cluster) { $cluster.Name } else { 'Standalone' }
                    PreviousState         = [string]$vmHost.ConnectionState
                    CurrentState          = [string]$updatedHost.ConnectionState
                    VMsEvacuatedCount     = $hostVMs.Count
                    DisconnectedIsoVMs    = ($vmsWithCd -join ', ')
                    VsanDataMigrationMode = $VsanDataMigrationMode
                    Timestamp             = Get-Date -Format 'o'
                }
            }
        }
        catch {
            Write-Error -Message "Failed to place ESXi host '$VMHostName' into Maintenance Mode: $_" -TargetObject $VMHostName
        }
    }
}
