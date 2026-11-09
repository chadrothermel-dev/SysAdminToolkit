@{
    RootModule        = 'SysAdminToolkit.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = 'a4f8d2c1-7b39-4e65-9c12-8b3d4e5f6a7b'
    Author            = 'Systems Engineering & Automation Team'
    CompanyName       = 'Enterprise IT Operations'
    Copyright         = '(c) 2026 Enterprise IT Operations. All rights reserved.'
    Description       = 'Unified PowerShell Systems Administration & Engineering Toolkit for Windows Server, Active Directory, Microsoft Azure, and VMware vSphere reporting, hardening, and remediation.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        # Windows Server & Active Directory - Reporting (6)
        'Get-WinServerHealthReport',
        'Get-WinADAccountAudit',
        'Get-WinADDomainHealthReport',
        'Get-WinCertificateExpiryReport',
        'Get-WinCriticalEventReport',
        'Get-WinLocalAdminAudit',

        # Windows Server & Active Directory - Action (5)
        'Repair-WinStoppedAutoService',
        'Clear-WinTempAndUpdateCache',
        'Unlock-WinADAccountSafe',
        'Disable-WinADStaleAccount',
        'Invoke-WinGPUpdateRemote',

        # Microsoft Azure - Reporting (2)
        'Get-AzOrphanedResourceReport',
        'Get-AzVMBackupAndStatusReport',

        # Microsoft Azure - Action (2)
        'Set-AzVMPowerStateBatch',
        'Remove-AzOrphanedDisk',

        # VMware vSphere - Reporting (4)
        'Get-VMwareSnapshotAudit',
        'Get-VMwareClusterCapacityReport',
        'Get-VMwareHostSecurityAudit',
        'Get-VMwareVMToolsAndHardwareReport',

        # VMware vSphere - Action (5)
        'Remove-VMwareStaleSnapshot',
        'Enter-VMwareHostMaintenanceSafe',
        'Set-VMwareHostLockdownMode',
        'Set-VMwareHostServiceHardening',
        'Update-VMwareToolsBatch',

        # Local Repository & Unified Reporting (2)
        'Publish-ToolkitToLocalRepo',
        'Export-ToolkitReport'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('WindowsServer', 'ActiveDirectory', 'Azure', 'VMware', 'PowerCLI', 'LockdownMode', 'SysAdmin', 'Automation', 'Reporting')
            ReleaseNotes = '1.1.0 release with 26 reporting, security auditing, and remediation cmdlets across Windows Server, Active Directory, Azure, and VMware vSphere (including ESXi Lockdown Mode and Host Hardening).'
        }
    }
}
