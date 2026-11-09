function Remove-AzOrphanedDisk {
    <#
    .SYNOPSIS
        Safely deletes unattached Azure Managed Disks, optionally creating a snapshot before deletion.
    .DESCRIPTION
        Removes unattached Azure Managed Disks (or those piped from Get-AzOrphanedResourceReport) with full ShouldProcess safety controls and optional pre-deletion snapshot backup.
    .PARAMETER ResourceGroupName
        Resource group containing the unattached managed disk.
    .PARAMETER DiskName
        Name of the unattached managed disk to remove.
    .PARAMETER CreateSnapshotFirst
        Creates an incremental snapshot in the same Resource Group before deleting the Managed Disk.
    .EXAMPLE
        PS C:\> Get-AzOrphanedResourceReport | Where-Object ResourceType -eq 'ManagedDisk' | Remove-AzOrphanedDisk -CreateSnapshotFirst -WhatIf
        Previews creating a safety snapshot and deleting all unattached managed disks.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ResourceName', 'Name')]
        [string]$DiskName,

        [Parameter()]
        [switch]$CreateSnapshotFirst
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName @('Az.Accounts', 'Az.Compute')
    }

    process {
        try {
            $disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DiskName -ErrorAction Stop
            if (-not [string]::IsNullOrEmpty($disk.ManagedBy) -or $disk.DiskState -ne 'Unattached') {
                Write-Warning "Skipping disk '$DiskName' in '$ResourceGroupName' because it is currently attached or not in Unattached state (State: $($disk.DiskState))."
                return
            }

            $snapshotName = $null
            $actionText = if ($CreateSnapshotFirst.IsPresent) {
                "Create safety snapshot and remove unattached Managed Disk ($($disk.DiskSizeGB) GB)"
            }
            else {
                "Permanently remove unattached Managed Disk ($($disk.DiskSizeGB) GB)"
            }

            if ($PSCmdlet.ShouldProcess("$DiskName (RG: $ResourceGroupName)", $actionText)) {
                if ($CreateSnapshotFirst.IsPresent) {
                    $snapshotName = "snap-$($DiskName)-$(Get-Date -Format 'yyyyMMddHHmm')"
                    $snapConfig = New-AzSnapshotConfig -SourceUri $disk.Id -Location $disk.Location -CreateOption Copy -Incremental -ErrorAction Stop
                    $null = New-AzSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotName -Snapshot $snapConfig -ErrorAction Stop
                }

                $null = Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DiskName -Force -ErrorAction Stop

                [PSCustomObject]@{
                    ResourceGroupName = $ResourceGroupName
                    DiskName          = $DiskName
                    DiskSizeGB        = $disk.DiskSizeGB
                    SafetySnapshot    = if ($snapshotName) { $snapshotName } else { 'None' }
                    ActionResult      = 'Deleted'
                    Timestamp         = Get-Date -Format 'o'
                }
            }
        }
        catch {
            Write-Error -Message "Failed to remove Azure Managed Disk '$DiskName' in '$ResourceGroupName': $_" -TargetObject $DiskName
        }
    }
}
