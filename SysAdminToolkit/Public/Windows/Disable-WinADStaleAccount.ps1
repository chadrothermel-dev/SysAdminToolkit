function Disable-WinADStaleAccount {
    <#
    .SYNOPSIS
        Safely disables inactive Active Directory user accounts, stamping Description and optionally moving to a quarantine OU.
    .DESCRIPTION
        Finds enabled Active Directory user accounts whose LastLogonDate is older than InactiveDays, automatically excludes privileged accounts (Domain Admins, Enterprise Admins, Schema Admins) and specified exclusion list accounts, stamps the Description attribute with a remediation note, disables the account, and optionally moves it to TargetDisabledOU.
    .PARAMETER InactiveDays
        Minimum days since LastLogonDate to consider an account stale. Default is 90.
    .PARAMETER SearchBase
        Optional OU DistinguishedName to scope the search.
    .PARAMETER ExcludeSamAccountName
        Array of SamAccountNames (such as service accounts or break-glass accounts) to exempt from disabling.
    .PARAMETER TargetDisabledOU
        Optional DistinguishedName of a quarantine/disabled users OU to move disabled accounts into.
    .EXAMPLE
        PS C:\> Disable-WinADStaleAccount -InactiveDays 90 -ExcludeSamAccountName "svc-sql", "adm-breakglass" -WhatIf
        Previews disabling enabled AD user accounts inactive for 90+ days while protecting privileged and excluded accounts.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateRange(30, 3650)]
        [int]$InactiveDays = 90,

        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [string[]]$ExcludeSamAccountName = @('krbtgt', 'Administrator', 'Guest'),

        [Parameter()]
        [string]$TargetDisabledOU
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName 'ActiveDirectory'
        $cutoffDate = (Get-Date).AddDays(-$InactiveDays)
        $privilegedGroups = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators')
    }

    process {
        try {
            $excludedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($ex in $ExcludeSamAccountName) {
                $null = $excludedSet.Add($ex)
            }

            foreach ($grp in $privilegedGroups) {
                try {
                    $members = Get-ADGroupMember -Identity $grp -Recursive -ErrorAction SilentlyContinue | Where-Object { $_.objectClass -eq 'user' }
                    foreach ($m in $members) {
                        $null = $excludedSet.Add($m.SamAccountName)
                    }
                }
                catch {
                    $null = $_
                }
            }

            $userParams = @{
                Filter     = 'Enabled -eq $true'
                Properties = @('SamAccountName', 'DisplayName', 'LastLogonDate', 'WhenCreated', 'Description', 'DistinguishedName')
                ErrorAction = 'Stop'
            }
            if (-not [string]::IsNullOrWhiteSpace($SearchBase)) {
                $userParams['SearchBase'] = $SearchBase
            }

            $staleUsers = Get-ADUser @userParams | Where-Object {
                ($null -eq $_.LastLogonDate -or $_.LastLogonDate -lt $cutoffDate) -and
                ($_.WhenCreated -lt $cutoffDate) -and
                (-not $excludedSet.Contains($_.SamAccountName))
            }

            $dateStamp = Get-Date -Format 'yyyy-MM-dd'
            foreach ($user in $staleUsers) {
                $actionDesc = "Disable stale AD account (LastLogonDate: $($user.LastLogonDate))" + $(if ($TargetDisabledOU) { " and move to '$TargetDisabledOU'" } else { '' })
                if ($PSCmdlet.ShouldProcess("$($user.SamAccountName) ($($user.DistinguishedName))", $actionDesc)) {
                    $newDesc = "[Disabled $dateStamp by SysAdminToolkit: Inactive >${InactiveDays}d] $($user.Description)".Trim()
                    Set-ADUser -Identity $user.DistinguishedName -Description $newDesc -ErrorAction Stop
                    Disable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop

                    if (-not [string]::IsNullOrWhiteSpace($TargetDisabledOU)) {
                        Move-ADObject -Identity $user.DistinguishedName -TargetPath $TargetDisabledOU -ErrorAction Stop
                    }

                    [PSCustomObject]@{
                        SamAccountName    = $user.SamAccountName
                        DisplayName       = $user.DisplayName
                        LastLogonDate     = $user.LastLogonDate
                        PreviousOU        = $user.DistinguishedName
                        MovedToOU         = if ($TargetDisabledOU) { $TargetDisabledOU } else { 'Unchanged' }
                        Status            = 'Disabled'
                        Timestamp         = Get-Date -Format 'o'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to disable stale Active Directory accounts: $_"
        }
    }
}
