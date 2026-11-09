function Invoke-WinGPUpdateRemote {
    <#
    .SYNOPSIS
        Triggers a non-interactive Group Policy refresh (gpupdate /force) across local or remote Windows servers.
    .DESCRIPTION
        Executes gpupdate.exe /target:computer (or both computer and user) /force /wait:0 on local or remote Windows servers via WinRM / Invoke-Command so policies apply immediately without hanging interactive sessions.
    .PARAMETER ComputerName
        One or more Windows Server hostnames. Defaults to localhost.
    .PARAMETER Target
        Group Policy target scope: Computer, User, or Both. Default is Computer.
    .PARAMETER Credential
        Optional PSCredential for WinRM remote execution.
    .EXAMPLE
        PS C:\> Invoke-WinGPUpdateRemote -ComputerName "srv-web01", "srv-web02" -Target Computer -Verbose
        Triggers a forced Computer Group Policy update on srv-web01 and srv-web02.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ServerName', 'HostName')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [ValidateSet('Computer', 'User', 'Both')]
        [string]$Target = 'Computer',

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Set-StrictMode -Version Latest
        $gpScriptBlock = {
            param($ScopeTarget)
            $gpArgs = @('/force', '/wait:0')
            if ($ScopeTarget -eq 'Computer') {
                $gpArgs = @('/target:computer') + $gpArgs
            }
            elseif ($ScopeTarget -eq 'User') {
                $gpArgs = @('/target:user') + $gpArgs
            }

            $output = & "$env:SystemRoot\System32\gpupdate.exe" @gpArgs 2>&1 | Out-String
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                TargetScope  = $ScopeTarget
                ExitCode     = $LASTEXITCODE
                Status       = if ($LASTEXITCODE -eq 0) { 'Success' } else { 'WarningOrError' }
                Output       = $output.Trim()
                Timestamp    = Get-Date -Format 'o'
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            if ($PSCmdlet.ShouldProcess($computer, "Invoke gpupdate /force (Target: $Target)")) {
                try {
                    $isLocal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '127.0.0.1') -or ($computer -eq '.')
                    if ($isLocal) {
                        & $gpScriptBlock -ScopeTarget $Target
                    }
                    else {
                        $icmParams = @{
                            ComputerName = $computer
                            ScriptBlock  = $gpScriptBlock
                            ArgumentList = @($Target)
                            ErrorAction  = 'Stop'
                        }
                        if ($PSBoundParameters.ContainsKey('Credential')) {
                            $icmParams['Credential'] = $Credential
                        }
                        Invoke-Command @icmParams | Select-Object -Property ComputerName, TargetScope, ExitCode, Status, Output, Timestamp
                    }
                }
                catch {
                    Write-Error -Message "Failed to invoke remote GPUpdate on '$computer': $_" -TargetObject $computer
                }
            }
        }
    }
}
