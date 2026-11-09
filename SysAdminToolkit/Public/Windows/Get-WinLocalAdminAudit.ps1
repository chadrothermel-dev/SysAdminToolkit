function Get-WinLocalAdminAudit {
    <#
    .SYNOPSIS
        Audits membership of the local Administrators group across local or remote Windows servers.
    .DESCRIPTION
        Queries members of the local Administrators group (SID S-1-5-32-544) on local or remote Windows servers to detect unauthorized local accounts, domain users, or orphaned SIDs.
    .PARAMETER ComputerName
        One or more Windows Server hostnames. Defaults to localhost.
    .PARAMETER Credential
        Optional PSCredential for WinRM remote execution.
    .EXAMPLE
        PS C:\> Get-WinLocalAdminAudit -ComputerName "srv-app01", "srv-sql01"
        Returns all members of the local Administrators group on srv-app01 and srv-sql01.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('ServerName', 'HostName')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        Set-StrictMode -Version Latest
        $localAdminScript = {
            $adminGroup = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
            $members = Get-LocalGroupMember -Group $adminGroup -ErrorAction Stop
            foreach ($member in $members) {
                [PSCustomObject]@{
                    ComputerName    = $env:COMPUTERNAME
                    GroupName       = $adminGroup.Name
                    MemberName      = $member.Name
                    ObjectClass     = $member.ObjectClass
                    PrincipalSource = [string]$member.PrincipalSource
                    SID             = $member.SID.Value
                    Timestamp       = Get-Date -Format 'o'
                }
            }
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                $isLocal = ($computer -eq $env:COMPUTERNAME) -or ($computer -eq 'localhost') -or ($computer -eq '127.0.0.1') -or ($computer -eq '.')
                if ($isLocal) {
                    & $localAdminScript
                }
                else {
                    $icmParams = @{
                        ComputerName = $computer
                        ScriptBlock  = $localAdminScript
                        ErrorAction  = 'Stop'
                    }
                    if ($PSBoundParameters.ContainsKey('Credential')) {
                        $icmParams['Credential'] = $Credential
                    }
                    Invoke-Command @icmParams | Select-Object -Property ComputerName, GroupName, MemberName, ObjectClass, PrincipalSource, SID, Timestamp
                }
            }
            catch {
                Write-Error -Message "Failed to audit local Administrators group on '$computer': $_" -TargetObject $computer
            }
        }
    }
}
