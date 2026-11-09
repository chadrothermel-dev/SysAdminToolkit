function Update-VMwareToolsBatch {
    <#
    .SYNOPSIS
        Upgrades VMware Tools on powered-on VMs with outdated tools without forcing a guest OS reboot by default.
    .DESCRIPTION
        Queries powered-on VMs (or accepts piped VMs from Get-VMwareVMToolsAndHardwareReport) where ToolsStatus is 'toolsOld' and runs Update-Tools with -NoReboot by default so production workloads do not unexpectedly restart.
    .PARAMETER VMName
        One or more VM names or wildcard patterns.
    .PARAMETER ClusterName
        Optional vSphere Cluster name filter.
    .PARAMETER AllowReboot
        If specified, allows the guest OS to reboot automatically if required by the VMware Tools upgrade. By default, -NoReboot is passed to Update-Tools.
    .PARAMETER RunAsync
        Executes the VMware Tools upgrade asynchronously.
    .EXAMPLE
        PS C:\> Update-VMwareToolsBatch -ClusterName "Prod-Cluster01" -WhatIf
        Previews upgrading VMware Tools (with -NoReboot) on all powered-on VMs in Prod-Cluster01 that have toolsOld status.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$VMName,

        [Parameter()]
        [string]$ClusterName,

        [Parameter()]
        [switch]$AllowReboot,

        [Parameter()]
        [switch]$RunAsync
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
            elseif ($PSBoundParameters.ContainsKey('VMName') -and $VMName.Count -gt 0) {
                Get-VM -Name $VMName -ErrorAction Stop
            }
            else {
                Get-VM -ErrorAction Stop
            }

            $outdatedVMs = $vms | Where-Object {
                $_.PowerState -eq 'PoweredOn' -and $_.ExtensionData.Guest.ToolsStatus -eq 'toolsOld'
            }

            foreach ($vm in $outdatedVMs) {
                $rebootNote = if ($AllowReboot.IsPresent) { 'Reboot Allowed' } else { 'NoReboot' }
                if ($PSCmdlet.ShouldProcess("VM '$($vm.Name)' (Current Tools: $($vm.ExtensionData.Guest.ToolsVersion))", "Update-Tools ($rebootNote)")) {
                    $updateParams = @{
                        VM          = $vm
                        ErrorAction = 'Stop'
                    }
                    if (-not $AllowReboot.IsPresent) {
                        $updateParams['NoReboot'] = $true
                    }
                    if ($RunAsync.IsPresent) {
                        $updateParams['RunAsync'] = $true
                    }

                    $null = Update-Tools @updateParams

                    [PSCustomObject]@{
                        VMName               = $vm.Name
                        PreviousToolsVersion = [string]$vm.ExtensionData.Guest.ToolsVersion
                        RebootPolicy         = $rebootNote
                        ExecutionMode        = if ($RunAsync.IsPresent) { 'Async' } else { 'Synchronous' }
                        Status               = 'UpgradeInitiated'
                        Timestamp            = Get-Date -Format 'o'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to execute batch VMware Tools upgrade: $_"
        }
    }
}
