function Clear-WinTempAndUpdateCache {
    <#
    .SYNOPSIS
        Reclaims disk space on Windows servers by clearing Temp directories and Windows Update download cache.
    .DESCRIPTION
        Safely deletes stale files in C:\Windows\Temp, user temp folders, and optionally stops the Windows Update service (wuauserv) to purge C:\Windows\SoftwareDistribution\Download, returning total space reclaimed in MB.
    .PARAMETER ComputerName
        One or more Windows Server hostnames. Defaults to localhost.
    .PARAMETER MinFileAgeHours
        Only delete temporary files last modified more than this many hours ago (prevents breaking active installers). Default is 24.
    .PARAMETER IncludeWindowsUpdateCache
        When specified, stops wuauserv, clears SoftwareDistribution\Download, and restarts wuauserv.
    .PARAMETER Credential
        Optional PSCredential for WinRM remote execution.
    .EXAMPLE
        PS C:\> Clear-WinTempAndUpdateCache -ComputerName "srv-web01" -IncludeWindowsUpdateCache -WhatIf
        Shows what temp directories and update caches would be purged on srv-web01.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [ValidateRange(0, 8760)]
        [int]$MinFileAgeHours = 24,

        [Parameter()]
        [switch]$IncludeWindowsUpdateCache,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Set-StrictMode -Version Latest

        $cleanupScriptBlock = {
            param($AgeHours, $ClearWUCache)
            $cutoff = (Get-Date).AddHours(-$AgeHours)
            $sysDrive = $env:SystemDrive

            $volBefore = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '$sysDrive'"
            $freeBeforeBytes = $volBefore.FreeSpace

            $targetPaths = @(
                (Join-Path -Path $env:SystemRoot -ChildPath 'Temp')
            )
            $userTempPaths = Get-ChildItem -Path (Join-Path -Path $sysDrive -ChildPath 'Users') -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path -Path $_.FullName -ChildPath 'AppData\Local\Temp' } |
                Where-Object { Test-Path -Path $_ }
            $targetPaths += $userTempPaths

            $filesRemoved = 0
            foreach ($folder in $targetPaths) {
                if (Test-Path -Path $folder) {
                    $items = Get-ChildItem -Path $folder -Recurse -Force -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt $cutoff }
                    foreach ($item in $items) {
                        try {
                            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                            $filesRemoved++
                        }
                        catch {
                            # Skip locked files in use by running processes
                            $null = $_
                        }
                    }
                }
            }

            if ($ClearWUCache) {
                $wuDownload = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\Download'
                if (Test-Path -Path $wuDownload) {
                    $wuService = Get-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
                    $wasRunning = ($null -ne $wuService -and $wuService.Status -eq 'Running')
                    try {
                        if ($wasRunning) {
                            Stop-Service -Name 'wuauserv' -Force -ErrorAction Stop
                        }
                        Get-ChildItem -Path $wuDownload -Recurse -Force -ErrorAction SilentlyContinue |
                            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    finally {
                        if ($wasRunning) {
                            Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
                        }
                    }
                }
            }

            $volAfter = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '$sysDrive'"
            $freeAfterBytes = $volAfter.FreeSpace
            $reclaimedMB = [math]::Round([math]::Max(0, ($freeAfterBytes - $freeBeforeBytes)) / 1MB, 2)

            [PSCustomObject]@{
                ComputerName            = $env:COMPUTERNAME
                FilesRemovedCount       = $filesRemoved
                ClearedUpdateCache      = [bool]$ClearWUCache
                SpaceReclaimedMB        = $reclaimedMB
                FreeSpaceAfterGB        = [math]::Round($freeAfterBytes / 1GB, 2)
                Timestamp               = Get-Date -Format 'o'
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            $actionDesc = "Clear temporary files older than $MinFileAgeHours hours (IncludeWindowsUpdateCache: $($IncludeWindowsUpdateCache.IsPresent))"
            if ($PSCmdlet.ShouldProcess($computer, $actionDesc)) {
                try {
                    $isLocal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '127.0.0.1') -or ($computer -eq '.')
                    if ($isLocal) {
                        & $cleanupScriptBlock -AgeHours $MinFileAgeHours -ClearWUCache $IncludeWindowsUpdateCache.IsPresent
                    }
                    else {
                        $icmParams = @{
                            ComputerName = $computer
                            ScriptBlock  = $cleanupScriptBlock
                            ArgumentList = @($MinFileAgeHours, $IncludeWindowsUpdateCache.IsPresent)
                            ErrorAction  = 'Stop'
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $icmParams['Credential'] = $Credential
                        }
                        Invoke-Command @icmParams | Select-Object -Property ComputerName, FilesRemovedCount, ClearedUpdateCache, SpaceReclaimedMB, FreeSpaceAfterGB, Timestamp
                    }
                }
                catch {
                    Write-Error -Message "Failed to clean temporary/update caches on '$computer': $_" -TargetObject $computer
                }
            }
        }
    }
}
