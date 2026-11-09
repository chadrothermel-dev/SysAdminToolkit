function Export-ToolkitReport {
    <#
    .SYNOPSIS
        Exports output from any SysAdminToolkit reporting or action command into a styled HTML dashboard, CSV, or JSON file.
    .DESCRIPTION
        Accepts pipeline objects from Get-Win*, Get-Az*, or Get-VMware* commands and formats them into a clean, responsive HTML report (with status color badges), CSV, or JSON file.
    .PARAMETER InputObject
        Objects piped from any SysAdminToolkit cmdlet.
    .PARAMETER OutputPath
        Destination file path (.html, .csv, or .json).
    .PARAMETER ReportTitle
        Title displayed at the top of the HTML report. Default is 'SysAdminToolkit Infrastructure Report'.
    .EXAMPLE
        PS C:\> Get-WinServerHealthReport | Export-ToolkitReport -OutputPath "C:\Reports\ServerHealth.html" -ReportTitle "Daily Windows Server Health"
        Generates a styled HTML report from the Windows Server health audit.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [psobject[]]$InputObject,

        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$ReportTitle = 'SysAdminToolkit Infrastructure Report'
    )

    begin {
        Set-StrictMode -Version Latest
        $collectedItems = [System.Collections.Generic.List[psobject]]::new()
    }

    process {
        if ($null -ne $InputObject) {
            foreach ($item in $InputObject) {
                if ($null -ne $item) {
                    $collectedItems.Add($item)
                }
            }
        }
    }

    end {
        try {
            $parentDir = Split-Path -Path $OutputPath -Parent
            if ($parentDir -and -not (Test-Path -Path $parentDir)) {
                $null = New-Item -Path $parentDir -ItemType Directory -Force -ErrorAction Stop
            }

            $extension = [System.IO.Path]::GetExtension($OutputPath).ToLowerInvariant()

            switch ($extension) {
                '.csv' {
                    $collectedItems | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                }
                '.json' {
                    $collectedItems | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding UTF8 -ErrorAction Stop
                }
                default {
                    $css = @"
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0f172a; color: #e2e8f0; margin: 24px; }
    h1 { color: #38bdf8; margin-bottom: 4px; font-size: 24px; }
    .meta { color: #94a3b8; font-size: 13px; margin-bottom: 20px; }
    table { border-collapse: collapse; width: 100%; background: #1e293b; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 12px rgba(0,0,0,0.3); }
    th { background: #334155; color: #f8fafc; text-align: left; padding: 10px 14px; font-size: 13px; text-transform: uppercase; letter-spacing: 0.04em; }
    td { padding: 10px 14px; border-bottom: 1px solid #334155; font-size: 13.5px; }
    tr:hover { background: #26354d; }
</style>
"@
                    $generatedTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
                    $preContent = "<h1>$([System.Net.WebUtility]::HtmlEncode($ReportTitle))</h1><div class='meta'>Generated: $generatedTime | Host: $($env:COMPUTERNAME) | Total Records: $($collectedItems.Count)</div>"

                    if ($collectedItems.Count -eq 0) {
                        $htmlBody = "$css $preContent <p>No records returned.</p>"
                    }
                    else {
                        $htmlBody = $collectedItems | ConvertTo-Html -Head $css -PreContent $preContent -Title $ReportTitle | Out-String
                    }

                    Set-Content -Path $OutputPath -Value $htmlBody -Encoding UTF8 -ErrorAction Stop
                }
            }

            Get-Item -LiteralPath $OutputPath -ErrorAction Stop
        }
        catch {
            Write-Error -Message "Failed to export toolkit report to '$OutputPath': $_"
        }
    }
}
