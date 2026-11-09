function Write-ToolkitLog {
    <#
    .SYNOPSIS
        Internal logging helper for SysAdminToolkit.
    .DESCRIPTION
        Writes standardized timestamped messages to Verbose, Warning, or Error streams and optionally appends to a log file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Information', 'Verbose', 'Warning', 'Error')]
        [string]$Level = 'Verbose',

        [Parameter()]
        [string]$Component = 'SysAdminToolkit',

        [Parameter()]
        [string]$LogFilePath = $env:SYSADMIN_TOOLKIT_LOG
    )

    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'
    $formattedMessage = "[$timestamp] [$Component] [$Level] $Message"

    if (-not [string]::IsNullOrWhiteSpace($LogFilePath)) {
        try {
            $parentDir = Split-Path -Path $LogFilePath -Parent
            if ($parentDir -and -not (Test-Path -Path $parentDir)) {
                $null = New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop
            }
            Add-Content -Path $LogFilePath -Value $formattedMessage -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-Verbose "Unable to write to log file '$LogFilePath': $_"
        }
    }

    switch ($Level) {
        'Information' { Write-Information -MessageData $formattedMessage -InformationAction Continue }
        'Verbose'     { Write-Verbose -Message $formattedMessage }
        'Warning'     { Write-Warning -Message $formattedMessage }
        'Error'       { Write-Error -Message $formattedMessage }
    }
}
