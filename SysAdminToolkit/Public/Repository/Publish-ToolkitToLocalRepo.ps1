function Publish-ToolkitToLocalRepo {
    <#
    .SYNOPSIS
        Registers a local folder or SMB network share as a PowerShell repository and publishes SysAdminToolkit to it.
    .DESCRIPTION
        Creates the target repository directory if it does not exist, registers it as a trusted PSResourceRepository (PSResourceGet) and/or PSRepository (PowerShellGet), and publishes the SysAdminToolkit module so it can be installed on demand via Install-PSResource or Install-Module.
    .PARAMETER RepositoryPath
        Local folder path or UNC share path for the local PowerShell repository (e.g. 'C:\LocalPSRepo' or '\\fileserver\PSRepo').
    .PARAMETER RepositoryName
        Friendly name for the registered local PowerShell repository. Default is 'LocalSysAdminRepo'.
    .EXAMPLE
        PS C:\> Publish-ToolkitToLocalRepo -RepositoryPath "C:\LocalPSRepo" -Verbose
        Registers C:\LocalPSRepo as 'LocalSysAdminRepo' and publishes SysAdminToolkit into it as a .nupkg package.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName = 'LocalSysAdminRepo'
    )

    begin {
        Set-StrictMode -Version Latest
        $moduleRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'SysAdminToolkit.psd1'
        if (-not (Test-Path -Path $manifestPath)) {
            throw [System.IO.FileNotFoundException]::new("Could not locate SysAdminToolkit.psd1 at '$manifestPath'.")
        }
    }

    process {
        if ($PSCmdlet.ShouldProcess("Repository '$RepositoryName' at '$RepositoryPath'", "Register local repository and publish SysAdminToolkit")) {
            try {
                if (-not (Test-Path -Path $RepositoryPath)) {
                    Write-ToolkitLog -Message "Creating local repository directory at '$RepositoryPath'..." -Component 'Publish-ToolkitToLocalRepo' -Level Verbose
                    $null = New-Item -Path $RepositoryPath -ItemType Directory -Force -ErrorAction Stop
                }

                $resolvedRepoPath = (Resolve-Path -Path $RepositoryPath -ErrorAction Stop).ProviderPath
                $publishedEngine  = $null

                # Prefer Microsoft.PowerShell.PSResourceGet if available
                $hasPSResourceGet = $null -ne (Get-Module -ListAvailable -Name 'Microsoft.PowerShell.PSResourceGet' | Select-Object -First 1)
                if ($hasPSResourceGet) {
                    Import-Module -Name 'Microsoft.PowerShell.PSResourceGet' -ErrorAction Stop -Verbose:$false
                    $existingResRepo = Get-PSResourceRepository -Name $RepositoryName -ErrorAction SilentlyContinue
                    if ($null -eq $existingResRepo) {
                        Register-PSResourceRepository -Name $RepositoryName -Uri $resolvedRepoPath -Trusted -ErrorAction Stop
                    }
                    else {
                        Set-PSResourceRepository -Name $RepositoryName -Uri $resolvedRepoPath -Trusted -ErrorAction Stop
                    }

                    Publish-PSResource -Path $moduleRoot -Repository $RepositoryName -SkipDependenciesCheck -ErrorAction Stop
                    $publishedEngine = 'PSResourceGet'
                }
                else {
                    Import-Module -Name 'PowerShellGet' -ErrorAction Stop -Verbose:$false
                    $existingRepo = Get-PSRepository -Name $RepositoryName -ErrorAction SilentlyContinue
                    if ($null -eq $existingRepo) {
                        Register-PSRepository -Name $RepositoryName -SourceLocation $resolvedRepoPath -PublishLocation $resolvedRepoPath -InstallationPolicy Trusted -ErrorAction Stop
                    }
                    else {
                        Set-PSRepository -Name $RepositoryName -SourceLocation $resolvedRepoPath -PublishLocation $resolvedRepoPath -InstallationPolicy Trusted -ErrorAction Stop
                    }

                    Publish-Module -Path $moduleRoot -Repository $RepositoryName -ErrorAction Stop
                    $publishedEngine = 'PowerShellGet'
                }

                $manifestData = Import-PowerShellDataFile -Path $manifestPath

                [PSCustomObject]@{
                    ModuleName        = 'SysAdminToolkit'
                    ModuleVersion     = $manifestData.ModuleVersion
                    RepositoryName    = $RepositoryName
                    RepositoryPath    = $resolvedRepoPath
                    PackageManager    = $publishedEngine
                    InstallCommand    = if ($publishedEngine -eq 'PSResourceGet') {
                        "Install-PSResource -Name SysAdminToolkit -Repository $RepositoryName -Scope CurrentUser"
                    }
                    else {
                        "Install-Module -Name SysAdminToolkit -Repository $RepositoryName -Scope CurrentUser"
                    }
                    Timestamp         = Get-Date -Format 'o'
                }
            }
            catch {
                Write-Error -Message "Failed to publish SysAdminToolkit to local repository '$RepositoryPath': $_"
            }
        }
    }
}
