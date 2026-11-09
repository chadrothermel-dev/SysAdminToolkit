function Assert-PrerequisiteModule {
    <#
    .SYNOPSIS
        Internal helper to verify required external modules are available and imported.
    .DESCRIPTION
        Checks whether required modules (such as ActiveDirectory, Az.Accounts, VMware.PowerCLI / VCF.PowerCLI / VMware.VimAutomation.Core) are installed and loaded before executing platform-specific commands.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ModuleName
    )

    foreach ($mod in $ModuleName) {
        if ($mod -eq 'VMware.PowerCLI') {
            # Support both VCF.PowerCLI (9.x) and VMware.PowerCLI (13.x) via VMware.VimAutomation.Core
            if (-not (Get-Module -Name 'VMware.VimAutomation.Core')) {
                $coreMod = Get-Module -ListAvailable -Name 'VMware.VimAutomation.Core' | Select-Object -First 1
                if ($null -eq $coreMod) {
                    $errorMsg = "Prerequisite module 'VMware.VimAutomation.Core' (part of VCF.PowerCLI or VMware.PowerCLI) is not installed. Install it using: Install-PSResource -Name 'VCF.PowerCLI' -Scope CurrentUser (or Install-Module -Name 'VMware.PowerCLI' -Scope CurrentUser)."
                    throw [System.InvalidOperationException]::new($errorMsg)
                }
                Import-Module -Name 'VMware.VimAutomation.Core' -Global -ErrorAction Stop -Verbose:$false
            }
            continue
        }

        if (-not (Get-Module -Name $mod)) {
            $available = Get-Module -ListAvailable -Name $mod | Select-Object -First 1
            if (-not $available) {
                $errorMsg = "Prerequisite module '$mod' is not installed. Install it using: Install-PSResource -Name '$mod' -Scope CurrentUser (or Install-Module -Name '$mod' -Scope CurrentUser)."
                throw [System.InvalidOperationException]::new($errorMsg)
            }
            Import-Module -Name $mod -Global -ErrorAction Stop -Verbose:$false
        }
    }
}
