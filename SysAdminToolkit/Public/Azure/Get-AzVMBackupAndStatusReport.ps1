function Get-AzVMBackupAndStatusReport {
    <#
    .SYNOPSIS
        Audits Azure Virtual Machines for power state, VM size, OS type, and Azure Backup protection status.
    .DESCRIPTION
        Queries Azure Virtual Machines across a subscription or specific resource group, retrieving runtime power state (running, deallocated, stopped) and checking whether each VM is protected by an Azure Recovery Services Vault.
    .PARAMETER ResourceGroupName
        Optional Resource Group name to filter VMs.
    .PARAMETER SkipBackupCheck
        Skips querying Recovery Services Vault backup status for faster execution on large environments.
    .EXAMPLE
        PS C:\> Get-AzVMBackupAndStatusReport -Verbose
        Returns status and backup compliance for all Azure VMs in the current subscription.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [string]$ResourceGroupName,

        [Parameter()]
        [switch]$SkipBackupCheck
    )

    begin {
        Set-StrictMode -Version Latest
        $requiredModules = @('Az.Accounts', 'Az.Compute')
        if (-not $SkipBackupCheck.IsPresent) {
            $requiredModules += 'Az.RecoveryServices'
        }
        Assert-PrerequisiteModule -ModuleName $requiredModules

        $currentCtx = Get-AzContext -ErrorAction Stop
        if ($null -eq $currentCtx) {
            throw [System.InvalidOperationException]::new("No active Azure session found. Run Connect-AzAccount first.")
        }
    }

    process {
        try {
            $vmParams = @{ Status = $true; ErrorAction = 'Stop' }
            if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
                $vmParams['ResourceGroupName'] = $ResourceGroupName
            }

            Write-ToolkitLog -Message "Retrieving Azure VM status list..." -Component 'Get-AzVMBackupAndStatusReport' -Level Verbose
            $vms = Get-AzVM @vmParams

            foreach ($vm in $vms) {
                $backupProtected = 'Skipped'
                $vaultId = $null

                if (-not $SkipBackupCheck.IsPresent) {
                    try {
                        $bkpStatus = Get-AzRecoveryServicesBackupStatus -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Type 'AzureVM' -ErrorAction Stop
                        $backupProtected = if ($bkpStatus.BackedUp) { 'Protected' } else { 'Unprotected' }
                        $vaultId = $bkpStatus.VaultId
                    }
                    catch {
                        $backupProtected = 'CheckFailed'
                    }
                }

                $vaultName = if ($vaultId) { ($vaultId -split '/')[-1] } else { 'None' }

                [PSCustomObject]@{
                    SubscriptionId      = $currentCtx.Subscription.Id
                    ResourceGroupName   = $vm.ResourceGroupName
                    VMName              = $vm.Name
                    Location            = $vm.Location
                    VMSize              = $vm.HardwareProfile.VmSize
                    OSType              = [string]$vm.StorageProfile.OsDisk.OsType
                    PowerState          = $vm.PowerState
                    ProvisioningState   = $vm.ProvisioningState
                    BackupCompliance    = $backupProtected
                    RecoveryVaultName   = $vaultName
                    Timestamp           = Get-Date -Format 'o'
                }
            }
        }
        catch {
            Write-Error -Message "Failed to generate Azure VM Backup and Status Report: $_"
        }
    }
}
