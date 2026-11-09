function Set-AzVMPowerStateBatch {
    <#
    .SYNOPSIS
        Starts, deallocates (stops), or restarts Azure Virtual Machines in bulk by Resource Group or Tag.
    .DESCRIPTION
        Performs batch power state changes on Azure VMs filtered by ResourceGroupName or Tag Key/Value pair, supporting -WhatIf, -Confirm, and asynchronous -NoWait execution.
    .PARAMETER Action
        Power action to perform: Start, StopDeallocate, or Restart.
    .PARAMETER ResourceGroupName
        Target Resource Group name.
    .PARAMETER TagName
        Optional Tag Key to filter target VMs (e.g. 'Environment' or 'AutoShutdown').
    .PARAMETER TagValue
        Optional Tag Value to match when TagName is provided.
    .PARAMETER NoWait
        Starts the operation asynchronously in Azure without blocking for each VM to finish.
    .EXAMPLE
        PS C:\> Set-AzVMPowerStateBatch -Action StopDeallocate -TagName "Environment" -TagValue "Dev" -WhatIf
        Previews deallocating all Azure VMs tagged with Environment=Dev.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Start', 'StopDeallocate', 'Restart')]
        [string]$Action,

        [Parameter()]
        [string]$ResourceGroupName,

        [Parameter()]
        [string]$TagName,

        [Parameter()]
        [string]$TagValue,

        [Parameter()]
        [switch]$NoWait
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName @('Az.Accounts', 'Az.Compute')
        if ([string]::IsNullOrWhiteSpace($ResourceGroupName) -and [string]::IsNullOrWhiteSpace($TagName)) {
            throw [System.ArgumentException]::new("You must specify at least -ResourceGroupName or -TagName to prevent accidental subscription-wide power state changes.")
        }
    }

    process {
        try {
            $getVmParams = @{ Status = $true; ErrorAction = 'Stop' }
            if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
                $getVmParams['ResourceGroupName'] = $ResourceGroupName
            }

            $vms = Get-AzVM @getVmParams
            if (-not [string]::IsNullOrWhiteSpace($TagName)) {
                $vms = $vms | Where-Object {
                    $null -ne $_.Tags -and $_.Tags.ContainsKey($TagName) -and
                    ([string]::IsNullOrWhiteSpace($TagValue) -or $_.Tags[$TagName] -eq $TagValue)
                }
            }

            foreach ($vm in $vms) {
                $targetLabel = "$($vm.Name) (RG: $($vm.ResourceGroupName), Current: $($vm.PowerState))"
                if ($PSCmdlet.ShouldProcess($targetLabel, "Azure VM Power Action: $Action")) {
                    $opParams = @{
                        Name              = $vm.Name
                        ResourceGroupName = $vm.ResourceGroupName
                        ErrorAction       = 'Stop'
                    }
                    if ($NoWait.IsPresent) {
                        $opParams['NoWait'] = $true
                    }

                    switch ($Action) {
                        'Start' {
                            $null = Start-AzVM @opParams
                        }
                        'StopDeallocate' {
                            $opParams['Force'] = $true
                            $null = Stop-AzVM @opParams
                        }
                        'Restart' {
                            $null = Restart-AzVM @opParams
                        }
                    }

                    [PSCustomObject]@{
                        VMName             = $vm.Name
                        ResourceGroupName  = $vm.ResourceGroupName
                        PreviousPowerState = $vm.PowerState
                        RequestedAction    = $Action
                        ExecutionMode      = if ($NoWait.IsPresent) { 'Async (NoWait)' } else { 'Synchronous' }
                        Status             = 'Submitted'
                        Timestamp          = Get-Date -Format 'o'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed executing batch Azure VM power state operation '$Action': $_"
        }
    }
}
