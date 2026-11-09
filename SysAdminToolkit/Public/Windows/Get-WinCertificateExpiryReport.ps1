function Get-WinCertificateExpiryReport {
    <#
    .SYNOPSIS
        Audits LocalMachine Personal certificates on local or remote Windows servers for upcoming expiration.
    .DESCRIPTION
        Scans Cert:\LocalMachine\My on one or more Windows servers and returns SSL/TLS/machine certificates expiring within ExpiringWithinDays (or already expired), including Subject, FriendlyName, Thumbprint, Issuer, DaysRemaining, and PrivateKey presence.
    .PARAMETER ComputerName
        One or more Windows Server hostnames. Defaults to localhost.
    .PARAMETER ExpiringWithinDays
        Return certificates expiring within this number of days. Default is 60.
    .PARAMETER IncludeExpired
        Include certificates that have already expired in the report. Enabled by default.
    .PARAMETER Credential
        Optional PSCredential for WinRM remote execution.
    .EXAMPLE
        PS C:\> Get-WinCertificateExpiryReport -ComputerName "srv-iis01", "srv-adfs01" -ExpiringWithinDays 45
        Returns all certificates in LocalMachine\My expiring within 45 days on srv-iis01 and srv-adfs01.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ServerName', 'HostName')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$ExpiringWithinDays = 60,

        [Parameter()]
        [bool]$IncludeExpired = $true,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Set-StrictMode -Version Latest
        $certScriptBlock = {
            param($DaysThreshold, $ShowExpired)
            $now = Get-Date
            $cutoff = $now.AddDays($DaysThreshold)

            $certs = Get-ChildItem -Path 'Cert:\LocalMachine\My' -ErrorAction Stop
            foreach ($cert in $certs) {
                $daysLeft = [math]::Floor(($cert.NotAfter - $now).TotalDays)
                if ($cert.NotAfter -le $cutoff -and ($ShowExpired -or $daysLeft -ge 0)) {
                    $status = if ($daysLeft -lt 0) { 'Expired' } elseif ($daysLeft -le 14) { 'Critical' } else { 'ExpiringSoon' }
                    [PSCustomObject]@{
                        ComputerName   = $env:COMPUTERNAME
                        Status         = $status
                        DaysRemaining  = $daysLeft
                        NotAfter       = $cert.NotAfter
                        Subject        = $cert.Subject
                        FriendlyName   = $cert.FriendlyName
                        Issuer         = $cert.Issuer
                        Thumbprint     = $cert.Thumbprint
                        HasPrivateKey  = $cert.HasPrivateKey
                    }
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $isLocal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '127.0.0.1') -or ($computer -eq '.')
                if ($isLocal) {
                    & $certScriptBlock -DaysThreshold $ExpiringWithinDays -ShowExpired $IncludeExpired
                }
                else {
                    $icmParams = @{
                        ComputerName = $computer
                        ScriptBlock  = $certScriptBlock
                        ArgumentList = @($ExpiringWithinDays, $IncludeExpired)
                        ErrorAction  = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $icmParams['Credential'] = $Credential
                    }
                    Invoke-Command @icmParams | Select-Object -Property ComputerName, Status, DaysRemaining, NotAfter, Subject, FriendlyName, Issuer, Thumbprint, HasPrivateKey
                }
            }
            catch {
                Write-Error -Message "Failed to query certificates on '$computer': $_" -TargetObject $computer
            }
        }
    }
}
