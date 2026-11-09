function Get-WinADAccountAudit {
    <#
    .SYNOPSIS
        Audits Active Directory user accounts for lockouts, inactivity, password expiration, and privileged access.
    .DESCRIPTION
        Queries Active Directory for locked-out accounts, enabled accounts inactive beyond a specified number of days, accounts with passwords never expiring, and members of high-privilege AD groups.
    .PARAMETER InactiveDays
        Number of days since LastLogonDate to consider an enabled account stale/inactive. Default is 90.
    .PARAMETER SearchBase
        Optional DistinguishedName (OU) to scope the user audit.
    .PARAMETER Server
        Optional Domain Controller hostname or domain FQDN.
    .EXAMPLE
        PS C:\> Get-WinADAccountAudit -InactiveDays 60 -Verbose
        Returns AD user account findings across the domain for accounts inactive 60+ days, locked out, or privileged.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$InactiveDays = 90,

        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [string]$Server
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName 'ActiveDirectory'
        $cutoffDate = (Get-Date).AddDays(-$InactiveDays)
        $privilegedGroupNames = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators')
    }

    process {
        try {
            Write-ToolkitLog -Message "Starting Active Directory account audit (Inactive cutoff: $($cutoffDate.ToString('yyyy-MM-dd')))..." -Component 'Get-WinADAccountAudit' -Level Verbose

            $adCommon = @{ ErrorAction = 'Stop' }
            if (-not [string]::IsNullOrWhiteSpace($Server)) {
                $adCommon['Server'] = $Server
            }

            # Gather privileged users
            $privilegedUsers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($groupName in $privilegedGroupNames) {
                try {
                    $members = Get-ADGroupMember @adCommon -Identity $groupName -Recursive -ErrorAction SilentlyContinue |
                        Where-Object { $_.objectClass -eq 'user' }
                    foreach ($member in $members) {
                        $null = $privilegedUsers.Add($member.SamAccountName)
                    }
                }
                catch {
                    Write-Verbose "Group '$groupName' could not be queried in current domain context: $_"
                }
            }

            $userParams = @{
                Filter     = '*'
                Properties = @(
                    'SamAccountName', 'DisplayName', 'Enabled', 'LockedOut',
                    'LastLogonDate', 'PasswordLastSet', 'PasswordNeverExpires',
                    'PasswordExpired', 'WhenCreated', 'DistinguishedName'
                )
            } + $adCommon

            if (-not [string]::IsNullOrWhiteSpace($SearchBase)) {
                $userParams['SearchBase'] = $SearchBase
            }

            $users = Get-ADUser @userParams

            foreach ($user in $users) {
                $findings = [System.Collections.Generic.List[string]]::new()
                $isPrivileged = $privilegedUsers.Contains($user.SamAccountName)

                if ($user.LockedOut) {
                    $findings.Add('LockedOut')
                }
                if ($user.Enabled -and ($null -eq $user.LastLogonDate -or $user.LastLogonDate -lt $cutoffDate) -and ($user.WhenCreated -lt $cutoffDate)) {
                    $findings.Add("Inactive_${InactiveDays}d")
                }
                if ($user.Enabled -and $user.PasswordNeverExpires) {
                    $findings.Add('PasswordNeverExpires')
                }
                if ($user.Enabled -and $user.PasswordExpired) {
                    $findings.Add('PasswordExpired')
                }
                if ($isPrivileged) {
                    $findings.Add('PrivilegedAccount')
                }

                if ($findings.Count -gt 0) {
                    $riskLevel = 'Low'
                    if ($isPrivileged -and ($user.PasswordNeverExpires -or ($findings -contains "Inactive_${InactiveDays}d"))) {
                        $riskLevel = 'High'
                    }
                    elseif ($user.LockedOut -or ($findings -contains "Inactive_${InactiveDays}d") -or $isPrivileged) {
                        $riskLevel = 'Medium'
                    }

                    [PSCustomObject]@{
                        SamAccountName       = $user.SamAccountName
                        DisplayName          = $user.DisplayName
                        Enabled              = $user.Enabled
                        LockedOut            = $user.LockedOut
                        IsPrivileged         = $isPrivileged
                        LastLogonDate        = $user.LastLogonDate
                        PasswordLastSet      = $user.PasswordLastSet
                        PasswordNeverExpires = $user.PasswordNeverExpires
                        Findings             = ($findings -join ', ')
                        RiskLevel            = $riskLevel
                        DistinguishedName    = $user.DistinguishedName
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Active Directory Account Audit failed: $_"
        }
    }
}
