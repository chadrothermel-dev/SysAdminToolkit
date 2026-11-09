function Get-AzOrphanedResourceReport {
    <#
    .SYNOPSIS
        Audits Azure subscriptions for orphaned/unattached resources that incur unnecessary cloud spend.
    .DESCRIPTION
        Scans one or more Azure subscriptions for unattached Managed Disks, unassociated Public IP addresses, unattached Network Interfaces (NICs), and empty Resource Groups.
    .PARAMETER SubscriptionId
        Optional array of Azure Subscription IDs to scan. Defaults to the current Az context subscription.
    .PARAMETER ExcludeTagName
        Tag name that exempts a resource from being flagged as orphaned (e.g. 'DoNotDelete').
    .EXAMPLE
        PS C:\> Get-AzOrphanedResourceReport -Verbose
        Scans the active Azure subscription and outputs all orphaned disks, public IPs, NICs, and empty resource groups.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$SubscriptionId,

        [Parameter()]
        [string]$ExcludeTagName = 'DoNotDelete'
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName @('Az.Accounts', 'Az.Compute', 'Az.Network', 'Az.Resources')

        $currentCtx = Get-AzContext -ErrorAction Stop
        if ($null -eq $currentCtx) {
            throw [System.InvalidOperationException]::new("No active Azure session found. Run Connect-AzAccount first.")
        }
    }

    process {
        $targetSubs = if ($PSBoundParameters.ContainsKey('SubscriptionId') -and $SubscriptionId.Count -gt 0) {
            $SubscriptionId
        }
        else {
            @($currentCtx.Subscription.Id)
        }

        foreach ($subId in $targetSubs) {
            try {
                Write-ToolkitLog -Message "Scanning Azure Subscription '$subId' for orphaned resources..." -Component 'Get-AzOrphanedResourceReport' -Level Verbose
                $null = Set-AzContext -SubscriptionId $subId -ErrorAction Stop

                # 1. Unattached Managed Disks
                $disks = Get-AzDisk -ErrorAction Stop | Where-Object {
                    [string]::IsNullOrEmpty($_.ManagedBy) -and $_.DiskState -eq 'Unattached'
                }
                foreach ($disk in $disks) {
                    if ($null -ne $disk.Tags -and $disk.Tags.ContainsKey($ExcludeTagName)) { continue }
                    [PSCustomObject]@{
                        SubscriptionId    = $subId
                        ResourceGroupName = $disk.ResourceGroupName
                        ResourceName      = $disk.Name
                        ResourceType      = 'ManagedDisk'
                        Location          = $disk.Location
                        SkuOrSize         = "$($disk.Sku.Name) ($($disk.DiskSizeGB) GB)"
                        Findings          = 'Unattached Managed Disk (ManagedBy is null)'
                        ResourceId        = $disk.Id
                        CreatedTime       = $disk.TimeCreated
                    }
                }

                # 2. Unassociated Public IPs
                $publicIps = Get-AzPublicIpAddress -ErrorAction Stop | Where-Object {
                    $null -eq $_.IpConfiguration
                }
                foreach ($pip in $publicIps) {
                    if ($null -ne $pip.Tag -and $pip.Tag.ContainsKey($ExcludeTagName)) { continue }
                    [PSCustomObject]@{
                        SubscriptionId    = $subId
                        ResourceGroupName = $pip.ResourceGroupName
                        ResourceName      = $pip.Name
                        ResourceType      = 'PublicIPAddress'
                        Location          = $pip.Location
                        SkuOrSize         = "$($pip.Sku.Name) ($($pip.PublicIpAllocationMethod))"
                        Findings          = 'Unassociated Public IP Address'
                        ResourceId        = $pip.Id
                        CreatedTime       = $null
                    }
                }

                # 3. Unattached Network Interfaces
                $nics = Get-AzNetworkInterface -ErrorAction Stop | Where-Object {
                    $null -eq $_.VirtualMachine -and $null -eq $_.PrivateEndpoint
                }
                foreach ($nic in $nics) {
                    if ($null -ne $nic.Tag -and $nic.Tag.ContainsKey($ExcludeTagName)) { continue }
                    [PSCustomObject]@{
                        SubscriptionId    = $subId
                        ResourceGroupName = $nic.ResourceGroupName
                        ResourceName      = $nic.Name
                        ResourceType      = 'NetworkInterface'
                        Location          = $nic.Location
                        SkuOrSize         = 'Standard NIC'
                        Findings          = 'Unattached Network Interface'
                        ResourceId        = $nic.Id
                        CreatedTime       = $null
                    }
                }

                # 4. Empty Resource Groups
                $allResourcesByRg = Get-AzResource -ErrorAction Stop | Group-Object -Property ResourceGroupName -AsHashTable -AsString
                $resourceGroups = Get-AzResourceGroup -ErrorAction Stop
                foreach ($rg in $resourceGroups) {
                    if ($null -ne $rg.Tags -and $rg.Tags.ContainsKey($ExcludeTagName)) { continue }
                    if ($null -eq $allResourcesByRg -or -not $allResourcesByRg.ContainsKey($rg.ResourceGroupName)) {
                        [PSCustomObject]@{
                            SubscriptionId    = $subId
                            ResourceGroupName = $rg.ResourceGroupName
                            ResourceName      = $rg.ResourceGroupName
                            ResourceType      = 'ResourceGroup'
                            Location          = $rg.Location
                            SkuOrSize         = 'N/A'
                            Findings          = 'Empty Resource Group (0 child resources)'
                            ResourceId        = $rg.ResourceId
                            CreatedTime       = $null
                        }
                    }
                }
            }
            catch {
                Write-Error -Message "Failed scanning Azure subscription '$subId' for orphaned resources: $_" -TargetObject $subId
            }
        }
    }
}
