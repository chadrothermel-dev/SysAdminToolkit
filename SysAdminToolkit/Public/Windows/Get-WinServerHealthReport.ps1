function Get-WinServerHealthReport {
    <#
    .SYNOPSIS
        Generates a comprehensive health report for local or remote Windows servers.
    .DESCRIPTION
        Queries Windows servers using CIM/WMI and WinRM to gather CPU utilization, memory usage, system drive capacity, uptime, pending reboot status (CBS, Windows Update, PendingFileRenameOperations), and stopped automatic services.
    .PARAMETER ComputerName
        One or more Windows Server hostnames or IP addresses. Defaults to localhost.
    .PARAMETER Credential
        Optional PSCredential for authenticating to remote systems.
    .PARAMETER FreeDiskSpaceThresholdPercent
        Percentage of free disk space below which a drive is flagged as warning. Default is 15.
    .EXAMPLE
        PS C:\> Get-WinServerHealthReport -ComputerName "srv-dc01", "srv-sql01" -Verbose
        Returns health metrics for srv-dc01 and srv-sql01.
    .EXAMPLE
        PS C:\> "srv-app01", "srv-web01" | Get-WinServerHealthReport | Export-ToolkitReport -OutputPath "C:\Reports\WinHealth.html"
        Pipes servers into the health check and exports an HTML dashboard.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('ServerName', 'HostName', 'CN')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [ValidateRange(1, 99)]
        [int]$FreeDiskSpaceThresholdPercent = 15
    )

    begin {
        Set-StrictMode -Version Latest
        $ignoredAutoServices = @(
            'sppsvc', 'RemoteRegistry', 'MapsBroker', 'edgeupdate',
            'gupdate', 'WbioSrvc', 'CDPSvc', 'tiledatamodelsvc', 'ShellHWDetection'
        )
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-ToolkitLog -Message "Querying health metrics on '$computer'..." -Component 'Get-WinServerHealthReport' -Level Verbose

            $cimSession = $null
            try {
                $isLocal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '127.0.0.1') -or ($computer -eq '.')

                $cimParams = @{ ErrorAction = 'Stop' }
                if (-not $isLocal) {
                    $sessionParams = @{
                        ComputerName = $computer
                        ErrorAction  = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $sessionParams['Credential'] = $Credential
                    }
                    $cimSession = New-CimSession @sessionParams
                    $cimParams['CimSession'] = $cimSession
                }

                $os = Get-CimInstance @cimParams -ClassName Win32_OperatingSystem
                $cpu = Get-CimInstance @cimParams -ClassName Win32_Processor
                $disks = Get-CimInstance @cimParams -ClassName Win32_LogicalDisk -Filter "DriveType = 3"
                $stoppedServices = Get-CimInstance @cimParams -ClassName Win32_Service -Filter "StartMode = 'Auto' AND State != 'Running'"

                $cpuLoadAvg = [math]::Round(($cpu | Measure-Object -Property LoadPercentage -Average).Average, 1)
                $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                $freeMemGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
                $usedMemPct = [math]::Round((($totalMemGB - $freeMemGB) / $totalMemGB) * 100, 1)
                $uptimeSpan = (Get-Date) - $os.LastBootUpTime

                $lowDisks = @()
                $systemDiskFreePct = $null
                foreach ($disk in $disks) {
                    if ($disk.Size -gt 0) {
                        $freePct = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
                        if ($disk.DeviceID -eq $env:SystemDrive -or $disk.DeviceID -eq 'C:') {
                            $systemDiskFreePct = $freePct
                        }
                        if ($freePct -lt $FreeDiskSpaceThresholdPercent) {
                            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                            $lowDisks += "$($disk.DeviceID) ($freePct% / ${freeGB}GB free)"
                        }
                    }
                }

                $filteredStopped = @(
                    $stoppedServices | Where-Object { $ignoredAutoServices -notcontains $_.Name } | Select-Object -ExpandProperty Name
                )

                # Check pending reboot indicators
                $pendingReboot = $false
                if ($isLocal) {
                    $cbsPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                    $wuPath  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
                    $smPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
                    if ((Test-Path -Path $cbsPath) -or (Test-Path -Path $wuPath)) {
                        $pendingReboot = $true
                    }
                    else {
                        $pfro = Get-ItemProperty -Path $smPath -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
                        if ($null -ne $pfro) { $pendingReboot = $true }
                    }
                }
                else {
                    $regResult = Invoke-CimMethod @cimParams -Namespace 'root\default' -ClassName 'StdRegProv' -MethodName 'EnumKey' -Arguments @{
                        hDefKey     = [uint32]2147483650 # HKLM
                        sSubKeyName = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                    } -ErrorAction SilentlyContinue
                    if ($null -ne $regResult -and $regResult.ReturnValue -eq 0) {
                        $pendingReboot = $true
                    }
                }

                $healthStatus = 'Healthy'
                if ($cpuLoadAvg -ge 90 -or $usedMemPct -ge 90 -or $lowDisks.Count -gt 0 -or $filteredStopped.Count -gt 0) {
                    $healthStatus = 'Warning'
                }
                if ($cpuLoadAvg -ge 98 -or $usedMemPct -ge 98) {
                    $healthStatus = 'Critical'
                }

                [PSCustomObject]@{
                    ComputerName          = $computer
                    HealthStatus          = $healthStatus
                    OSCaption             = $os.Caption
                    OSVersion             = $os.Version
                    UptimeDays            = [math]::Round($uptimeSpan.TotalDays, 1)
                    LastBootTime          = $os.LastBootUpTime
                    CPULoadPercent        = $cpuLoadAvg
                    MemoryUsedPercent     = $usedMemPct
                    MemoryTotalGB         = $totalMemGB
                    SystemDriveFreePct    = $systemDiskFreePct
                    LowSpaceDrives        = ($lowDisks -join '; ')
                    StoppedAutoServices   = ($filteredStopped -join ', ')
                    StoppedAutoSvcCount   = $filteredStopped.Count
                    PendingReboot         = $pendingReboot
                    Timestamp             = Get-Date -Format 'o'
                }
            }
            catch {
                Write-Error -Message "Failed to collect Windows health report from '$computer': $_" -TargetObject $computer
            }
            finally {
                if ($null -ne $cimSession) {
                    Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
