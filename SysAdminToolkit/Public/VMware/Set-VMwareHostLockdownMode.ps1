function Set-VMwareHostLockdownMode {
    <#
    .SYNOPSIS
        Enables, disables, or updates Lockdown Mode and Exception Users on VMware ESXi hosts.
    .DESCRIPTION
        Configures ESXi Host Lockdown Mode (Disabled, Normal, or Strict) using the vSphere HostAccessManager API (ChangeLockdownMode) and optionally adds or removes Lockdown Exception Users (UpdateLockdownExceptions).
        WARNING: LockdownStrict completely disables the Direct Console User Interface (DCUI) service. If vCenter becomes unavailable while in Strict Lockdown Mode and SSH/Exception users are not accessible, the host cannot be managed locally without a reinstall.
    .PARAMETER VMHostName
        One or more ESXi hostnames or wildcard patterns. Accepts pipeline input.
    .PARAMETER ClusterName
        Optional vSphere Cluster name to target all connected ESXi hosts in that cluster.
    .PARAMETER LockdownState
        Target Lockdown Mode state:
        - Disabled (lockdownDisabled): Disables Lockdown Mode; local root/DCUI login allowed.
        - Normal (lockdownNormal): Enables Normal Lockdown Mode; host only accessible via vCenter or DCUI (for authorized users).
        - Strict (lockdownStrict): Enables Strict Lockdown Mode; DCUI is stopped and host is only manageable via vCenter.
    .PARAMETER ExceptionUsersToAdd
        Optional array of local/AD usernames to add to the ESXi Lockdown Mode Exception Users list (e.g. service accounts for backup/CIM monitoring).
    .PARAMETER ExceptionUsersToRemove
        Optional array of usernames to remove from the ESXi Lockdown Mode Exception Users list.
    .PARAMETER ForceStrictLockdown
        Required safety switch when specifying LockdownState = 'Strict' to acknowledge that DCUI access will be disabled.
    .EXAMPLE
        PS C:\> Set-VMwareHostLockdownMode -ClusterName "Prod-Cluster01" -LockdownState Normal -WhatIf
        Previews enabling Normal Lockdown Mode on all ESXi hosts in Prod-Cluster01.
    .EXAMPLE
        PS C:\> Set-VMwareHostLockdownMode -VMHostName "esxi01.corp.local" -LockdownState Disabled -Verbose
        Disables Lockdown Mode on esxi01.corp.local for emergency maintenance or troubleshooting.
    .EXAMPLE
        PS C:\> Set-VMwareHostLockdownMode -VMHostName "esxi01.corp.local" -LockdownState Normal -ExceptionUsersToAdd "svc-veeam"
        Enables Normal Lockdown Mode and adds svc-veeam to the host's Lockdown Exception Users list.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$VMHostName,

        [Parameter()]
        [string]$ClusterName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Disabled', 'Normal', 'Strict')]
        [string]$LockdownState,

        [Parameter()]
        [string[]]$ExceptionUsersToAdd,

        [Parameter()]
        [string[]]$ExceptionUsersToRemove,

        [Parameter()]
        [switch]$ForceStrictLockdown
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName 'VMware.PowerCLI'
        if ($null -eq $Global:DefaultVIServers -or $Global:DefaultVIServers.Count -eq 0) {
            throw [System.InvalidOperationException]::new("No active vCenter connection found. Run Connect-VIServer first.")
        }

        if ($LockdownState -eq 'Strict' -and -not $ForceStrictLockdown.IsPresent) {
            throw [System.InvalidOperationException]::new("Setting LockdownState to 'Strict' disables the ESXi DCUI completely. If vCenter goes down, you may be locked out of the host. Re-run with -ForceStrictLockdown to confirm.")
        }

        $apiModeMap = @{
            'Disabled' = 'lockdownDisabled'
            'Normal'   = 'lockdownNormal'
            'Strict'   = 'lockdownStrict'
        }
        $targetApiMode = $apiModeMap[$LockdownState]
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
                $hostView = Get-View -Id $vmHost.ExtensionData.ConfigManager.HostAccessManager -ErrorAction Stop
                $previousMode = [string]$hostView.LockdownMode

                $actionDesc = "Set Lockdown Mode from '$previousMode' to '$targetApiMode'"
                if ($PSCmdlet.ShouldProcess("ESXi Host '$($vmHost.Name)'", $actionDesc)) {
                    # Update exception users if requested
                    if (($null -ne $ExceptionUsersToAdd -and $ExceptionUsersToAdd.Count -gt 0) -or ($null -ne $ExceptionUsersToRemove -and $ExceptionUsersToRemove.Count -gt 0)) {
                        $currentExceptions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        foreach ($existingUser in $hostView.QueryLockdownExceptions()) {
                            $null = $currentExceptions.Add($existingUser)
                        }
                        if ($null -ne $ExceptionUsersToAdd) {
                            foreach ($uAdd in $ExceptionUsersToAdd) {
                                $null = $currentExceptions.Add($uAdd)
                            }
                        }
                        if ($null -ne $ExceptionUsersToRemove) {
                            foreach ($uRem in $ExceptionUsersToRemove) {
                                $null = $currentExceptions.Remove($uRem)
                            }
                        }
                        $hostView.UpdateLockdownExceptions([string[]]@($currentExceptions))
                    }

                    # Change lockdown mode via HostAccessManager
                    if ($previousMode -ne $targetApiMode) {
                        $hostView.ChangeLockdownMode($targetApiMode)
                    }

                    # Refresh view to confirm new state
                    $hostView.UpdateViewData()
                    $updatedExceptions = @($hostView.QueryLockdownExceptions())

                    [PSCustomObject]@{
                        VMHostName         = $vmHost.Name
                        PreviousLockdown   = $previousMode
                        CurrentLockdown    = [string]$hostView.LockdownMode
                        ExceptionUsers     = ($updatedExceptions -join ', ')
                        ConnectionState    = [string]$vmHost.ConnectionState
                        Timestamp          = Get-Date -Format 'o'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to configure Lockdown Mode on ESXi host(s): $_"
        }
    }
}
