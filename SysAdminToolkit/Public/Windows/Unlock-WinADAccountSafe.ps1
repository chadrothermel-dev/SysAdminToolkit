function Unlock-WinADAccountSafe {
    <#
    .SYNOPSIS
        Unlocks locked-out Active Directory user accounts and reports the lockout timestamp.
    .DESCRIPTION
        Queries Active Directory (targeting the PDC Emulator when possible for immediate replication) to unlock a specified user or all currently locked-out user accounts with ShouldProcess safety controls.
    .PARAMETER Identity
        Optional SamAccountName or DistinguishedName to unlock. If omitted and -AllLockedOut is specified, unlocks all locked-out AD user accounts.
    .PARAMETER AllLockedOut
        When specified, searches for and unlocks all currently locked-out AD user accounts.
    .PARAMETER Server
        Optional Domain Controller hostname. Defaults to the domain's PDC Emulator.
    .EXAMPLE
        PS C:\> Unlock-WinADAccountSafe -Identity "jdoe" -Verbose
        Unlocks the AD account 'jdoe' on the PDC Emulator.
    .EXAMPLE
        PS C:\> Unlock-WinADAccountSafe -AllLockedOut -WhatIf
        Previews unlocking all currently locked-out user accounts in Active Directory.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('SamAccountName')]
        [string]$Identity,

        [Parameter()]
        [switch]$AllLockedOut,

        [Parameter()]
        [string]$Server
    )

    begin {
        Set-StrictMode -Version Latest
        Assert-PrerequisiteModule -ModuleName 'ActiveDirectory'
    }

    process {
        try {
            $targetServer = $Server
            if ([string]::IsNullOrWhiteSpace($targetServer)) {
                $pdc = (Get-ADDomain -ErrorAction SilentlyContinue).PDCEmulator
                if (-not [string]::IsNullOrWhiteSpace($pdc)) {
                    $targetServer = $pdc
                }
            }

            $adCommon = @{ ErrorAction = 'Stop' }
            if (-not [string]::IsNullOrWhiteSpace($targetServer)) {
                $adCommon['Server'] = $targetServer
            }

            $targetUsers = @()
            if ($AllLockedOut.IsPresent) {
                $lockedRefs = Search-ADAccount @adCommon -LockedOut -UsersOnly
                foreach ($ref in $lockedRefs) {
                    $targetUsers += Get-ADUser @adCommon -Identity $ref.SamAccountName -Properties LockedOut, AccountLockoutTime, BadLogonCount, DisplayName
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Identity)) {
                $targetUsers += Get-ADUser @adCommon -Identity $Identity -Properties LockedOut, AccountLockoutTime, BadLogonCount, DisplayName
            }
            else {
                throw [System.ArgumentException]::new("Specify either -Identity <SamAccountName> or -AllLockedOut.")
            }

            foreach ($user in $targetUsers) {
                if (-not $user.LockedOut) {
                    Write-Verbose "User '$($user.SamAccountName)' is not currently locked out."
                    continue
                }

                if ($PSCmdlet.ShouldProcess("AD User '$($user.SamAccountName)' ($($user.DisplayName))", "Unlock-ADAccount on '$targetServer'")) {
                    Unlock-ADAccount @adCommon -Identity $user.DistinguishedName

                    [PSCustomObject]@{
                        SamAccountName     = $user.SamAccountName
                        DisplayName        = $user.DisplayName
                        LockoutTime        = $user.AccountLockoutTime
                        DomainController   = $targetServer
                        Status             = 'Unlocked'
                        Timestamp          = Get-Date -Format 'o'
                    }
                }
            }
        }
        catch {
            Write-Error -Message "Failed to unlock Active Directory account: $_"
        }
    }
}
