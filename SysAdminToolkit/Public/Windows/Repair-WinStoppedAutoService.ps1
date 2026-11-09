function Repair-WinStoppedAutoService {
    <#
    .SYNOPSIS
        Finds and restarts stopped Automatic services on local or remote Windows servers.
    .DESCRIPTION
        Queries Windows servers for services configured with StartMode = 'Auto' that are not currently Running, excludes benign OS trigger-start services, and restarts them with ShouldProcess confirmation.
    .PARAMETER ComputerName
        One or more Windows Server hostnames or IP addresses. Defaults to localhost.
    .PARAMETER ExcludeServiceName
        Service names to skip during remediation. Includes benign Windows trigger-start services by default.
    .PARAMETER Credential
        Optional PSCredential for remote CIM session connections.
    .EXAMPLE
        PS C:\> Repair-WinStoppedAutoService -ComputerName "srv-app01" -WhatIf
        Shows which stopped automatic services would be restarted on srv-app01 without making changes.
    .EXAMPLE
        PS C:\> Repair-WinStoppedAutoService -ComputerName "srv-app01", "srv-web01" -Verbose
        Restarts stopped automatic services on srv-app01 and srv-web01 and reports remediation status.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('ServerName', 'HostName')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [string[]]$ExcludeServiceName = @(
            'sppsvc', 'RemoteRegistry', 'MapsBroker', 'edgeupdate',
            'gupdate', 'WbioSrvc', 'CDPSvc', 'tiledatamodelsvc', 'ShellHWDetection'
        ),

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Set-StrictMode -Version Latest
    }

    process {
        foreach ($computer in $ComputerName) {
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

                $stoppedServices = Get-CimInstance @cimParams -ClassName Win32_Service -Filter "StartMode = 'Auto' AND State != 'Running'" |
                    Where-Object { $ExcludeServiceName -notcontains $_.Name }

                foreach ($svc in $stoppedServices) {
                    $targetDesc = "$($svc.Name) ($($svc.DisplayName)) on $computer"
                    if ($PSCmdlet.ShouldProcess($targetDesc, 'Start-Service via CIM')) {
                        $invokeResult = Invoke-CimMethod -InputObject $svc -MethodName 'StartService' -ErrorAction Stop
                        $status = if ($invokeResult.ReturnValue -eq 0) { 'Started' } else { "Failed (ReturnCode: $($invokeResult.ReturnValue))" }

                        [PSCustomObject]@{
                            ComputerName = $computer
                            ServiceName  = $svc.Name
                            DisplayName  = $svc.DisplayName
                            PreviousState = $svc.State
                            Remediation  = $status
                            ReturnCode   = $invokeResult.ReturnValue
                            Timestamp    = Get-Date -Format 'o'
                        }
                    }
                }
            }
            catch {
                Write-Error -Message "Failed to remediate stopped automatic services on '$computer': $_" -TargetObject $computer
            }
            finally {
                if ($null -ne $cimSession) {
                    Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
