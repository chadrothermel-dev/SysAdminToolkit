function Get-WinCriticalEventReport {
    <#
    .SYNOPSIS
        Queries Windows System and Security event logs via Get-WinEvent for high-priority operational and security events.
    .DESCRIPTION
        Hunts for high-impact Windows events over the past Hours window using Get-WinEvent -FilterHashtable:
        - System Log: 41 (Kernel-Power unexpected reboot), 1074 (Planned restart/shutdown), 6008 (Dirty shutdown), 7031/7034 (Service crash), 7/11/55/153 (Disk/NTFS errors)
        - Security Log: 4740 (AD User Account Lockout), 4720 (User Account Created), 4728/4732 (Member added to privileged group)
    .PARAMETER ComputerName
        One or more Windows Server hostnames. Defaults to localhost.
    .PARAMETER Hours
        Lookback window in hours. Default is 24.
    .PARAMETER MaxEventsPerServer
        Maximum matching events to return per server. Default is 100.
    .PARAMETER IncludeSecurityEvents
        When specified, also queries the Security event log (requires elevation / Audit privileges).
    .PARAMETER Credential
        Optional PSCredential for remote queries.
    .EXAMPLE
        PS C:\> Get-WinCriticalEventReport -ComputerName "localhost" -Hours 48
        Returns unexpected reboots, service crashes, and disk errors from the System log over the past 48 hours.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ServerName', 'HostName')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [ValidateRange(1, 2160)]
        [int]$Hours = 24,

        [Parameter()]
        [ValidateRange(1, 5000)]
        [int]$MaxEventsPerServer = 100,

        [Parameter()]
        [switch]$IncludeSecurityEvents,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Set-StrictMode -Version Latest
        $startTime = (Get-Date).AddHours(-$Hours)
        $systemEventIds   = @(41, 1074, 6008, 7031, 7034, 7, 11, 55, 153)
        $securityEventIds = @(4740, 4720, 4728, 4732)
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $isLocal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '127.0.0.1') -or ($computer -eq '.')
                $winEventCommon = @{
                    MaxEvents   = $MaxEventsPerServer
                    ErrorAction = 'SilentlyContinue'
                }
                if (-not $isLocal) {
                    $winEventCommon['ComputerName'] = $computer
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $winEventCommon['Credential'] = $Credential
                    }
                }

                $sysFilter = @{
                    LogName   = 'System'
                    Id        = $systemEventIds
                    StartTime = $startTime
                }
                $events = @(Get-WinEvent @winEventCommon -FilterHashtable $sysFilter)

                if ($IncludeSecurityEvents.IsPresent) {
                    $secFilter = @{
                        LogName   = 'Security'
                        Id        = $securityEventIds
                        StartTime = $startTime
                    }
                    $events += @(Get-WinEvent @winEventCommon -FilterHashtable $secFilter)
                }

                foreach ($evt in ($events | Sort-Object -Property TimeCreated -Descending)) {
                    $firstLine = ($evt.Message -split "`r?`n")[0]
                    [PSCustomObject]@{
                        ComputerName = $computer
                        TimeCreated  = $evt.TimeCreated
                        LogName      = $evt.LogName
                        EventId      = $evt.Id
                        Level        = $evt.LevelDisplayName
                        ProviderName = $evt.ProviderName
                        Summary      = $firstLine
                    }
                }
            }
            catch {
                Write-Error -Message "Failed querying critical events on '$computer': $_" -TargetObject $computer
            }
        }
    }
}
