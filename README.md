# SysAdminToolkit (v1.1.0)

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.x-5391FE?logo=powershell&logoColor=white)
![Platform](https://img.shields.io/badge/Platforms-Windows%20Server%20%7C%20Azure%20%7C%20VMware%20vSphere-0078D4)
![Cmdlets](https://img.shields.io/badge/Exported%20Cmdlets-26-success)
![Tests](https://img.shields.io/badge/Pester%20v5-Passing-brightgreen)

**`SysAdminToolkit`** is a unified, enterprise-grade PowerShell module designed for **Systems Administrators and Systems Engineers**. It packages **26 high-value Reporting and Action (Remediation) cmdlets** for **Windows Server**, **Active Directory**, **VMware vSphere / VCF (PowerCLI)**, and **Microsoft Azure** into a single module that can be published to a local repository (folder or SMB file share) and installed on demand.

---

## Key Features

- **Unified Single-Module Architecture**: Keep one module in a local repository or network share and install it whenever needed via `Install-PSResource` or `Install-Module`.
- **Safe by Default (`SupportsShouldProcess`)**: Every state-changing (`Action`) cmdlet supports `-WhatIf` and `-Confirm`, with high-impact safety guards (such as `-ForceStrictLockdown` on ESXi Strict Lockdown Mode, backup snapshot exclusions on VMware snapshot cleanup, and automatic privileged group exclusions on AD stale account disabling).
- **Lazy Prerequisite Verification**: You don't need every vendor SDK installed to import `SysAdminToolkit`. Each cmdlet checks for its specific prerequisite module (`ActiveDirectory`, `Az.*`, or `VCF.PowerCLI` / `VMware.PowerCLI`) only when invoked.
- **Built-in HTML Dashboard, CSV, & JSON Exporter**: Pipe any `Get-*` toolkit command directly into `Export-ToolkitReport` to generate a dark-themed HTML report, CSV, or JSON artifact.

---

## Repository Structure

```text
SysAdminToolkit/
├── SysAdminToolkit/
│   ├── SysAdminToolkit.psd1                        # Module Manifest (v1.1.0, 26 exported cmdlets)
│   ├── SysAdminToolkit.psm1                        # Root module loader
│   ├── Private/
│   │   ├── Assert-PrerequisiteModule.ps1           # Lazy-loads AD, Az, or PowerCLI modules
│   │   └── Write-ToolkitLog.ps1                    # Timestamped stream & file logging helper
│   └── Public/
│       ├── Windows/                                # 11 Windows Server & Active Directory cmdlets
│       ├── VMware/                                 # 9 VMware vSphere / ESXi cmdlets
│       ├── Azure/                                  # 4 Microsoft Azure cmdlets
│       └── Repository/                             # 2 Local Repo packaging & HTML/CSV/JSON report cmdlets
├── Tests/
│   └── SysAdminToolkit.Tests.ps1                   # Pester v5 validation suite
└── README.md
```

---

## Complete Cmdlet Reference (26 Tools)

### 1. Windows Server & Active Directory (11 Cmdlets)

| Cmdlet | Category | Description |
| :--- | :---: | :--- |
| **`Get-WinServerHealthReport`** | Reporting | Queries local or remote servers via CIM/WinRM for CPU load, memory usage, system drive free %, low-space drives, uptime, pending reboot flags (`CBS`, `WindowsUpdate`, `PendingFileRenameOperations`), and stopped automatic services. |
| **`Get-WinADAccountAudit`** | Reporting | Audits Active Directory user accounts for lockouts, inactivity (`-InactiveDays 90`), non-expiring passwords, expired passwords, and membership in privileged groups (`Domain Admins`, `Enterprise Admins`, `Schema Admins`). |
| **`Get-WinADDomainHealthReport`** | Reporting | Audits Domain Controllers for Forest/Domain FSMO role holders, inbound replication failures (`Get-ADReplicationFailure`), Global Catalog/RODC status, and core DC service health (`NTDS`, `DNS`, `Netlogon`, `Kdc`, `DFSR`, `W32Time`). |
| **`Get-WinCertificateExpiryReport`** | Reporting | Scans `Cert:\LocalMachine\My` across local or remote Windows servers for SSL/TLS/machine certificates expiring within `-ExpiringWithinDays` (default `60`) or already expired. |
| **`Get-WinCriticalEventReport`** | Reporting | Uses `Get-WinEvent -FilterHashtable` to hunt System and Security logs for unexpected reboots (`41`, `6008`), planned restarts (`1074`), service crashes (`7031`, `7034`), disk/NTFS errors (`7`, `11`, `55`, `153`), and AD account lockouts (`4740`). |
| **`Get-WinLocalAdminAudit`** | Reporting | Audits members of the local `Administrators` group (`S-1-5-32-544`) across local or remote Windows servers to detect unauthorized accounts or orphaned SIDs. |
| **`Repair-WinStoppedAutoService`** | Action | Finds and starts stopped `Automatic` services on local/remote servers while excluding benign Windows trigger-start services (`sppsvc`, `RemoteRegistry`, `gupdate`, `edgeupdate`, etc.). |
| **`Clear-WinTempAndUpdateCache`** | Action | Purges stale files in `C:\Windows\Temp`, user `AppData\Local\Temp` directories, and optionally stops `wuauserv` to clean `SoftwareDistribution\Download` (`-IncludeWindowsUpdateCache`), returning total MB reclaimed. |
| **`Unlock-WinADAccountSafe`** | Action | Unlocks a specified locked-out AD user (`-Identity`) or all currently locked-out AD user accounts (`-AllLockedOut`), automatically targeting the domain's **PDC Emulator**. |
| **`Disable-WinADStaleAccount`** | Action | Safely disables enabled AD user accounts inactive beyond `-InactiveDays` (automatically excluding privileged AD groups and `-ExcludeSamAccountName`), stamps the `Description` with the date, and optionally moves them to `-TargetDisabledOU`. |
| **`Invoke-WinGPUpdateRemote`** | Action | Triggers non-interactive `gpupdate.exe /force /wait:0` across local or remote Windows servers via WinRM (`Computer`, `User`, or `Both`). |

---

### 2. VMware vSphere / VCF PowerCLI (9 Cmdlets)

| Cmdlet | Category | Description |
| :--- | :---: | :--- |
| **`Get-VMwareHostSecurityAudit`** | Reporting | Audits ESXi hosts across clusters for **Lockdown Mode** (`lockdownDisabled`, `lockdownNormal`, `lockdownStrict`), Lockdown Exception Users, SSH (`TSM-SSH`) state/policy, ESXi Shell (`TSM`) state/policy, NTP daemon/servers, and remote Syslog host. |
| **`Get-VMwareVMToolsAndHardwareReport`** | Reporting | Audits VMs for VMware Tools status (`toolsOk`, `toolsOld`, `toolsNotInstalled`, `toolsNotRunning`), VM Hardware Version (`vmx-*`), connected CD/DVD ISO mounts, and CPU/Memory Limits. |
| **`Get-VMwareSnapshotAudit`** | Reporting | Finds VM snapshots older than `-MinAgeDays` (default `3`) or larger than `-MinSizeGB` to prevent delta-disk latency and backup failures. |
| **`Get-VMwareClusterCapacityReport`** | Reporting | Reports cluster vCPU-to-pCore oversubscription ratios, memory utilization, HA/DRS configuration, connected/maintenance host counts, and lowest free datastore capacity. |
| **`Set-VMwareHostLockdownMode`** | Action | Enables or disables ESXi **Lockdown Mode** (`Disabled`, `Normal`, `Strict`) via `HostAccessManager.ChangeLockdownMode()` and updates **Lockdown Exception Users** (`-ExceptionUsersToAdd` / `-ExceptionUsersToRemove`). Requires `-ForceStrictLockdown` for `Strict` mode. |
| **`Set-VMwareHostServiceHardening`** | Action | Starts or stops ESXi host services (`TSM-SSH`, `TSM`, `ntpd`, `DCUI`) and sets their startup policy (`off`, `on`, `automatic`) across hosts or clusters. |
| **`Update-VMwareToolsBatch`** | Action | Upgrades VMware Tools on powered-on VMs with `toolsOld` status using `-NoReboot` by default so guest workloads do not unexpectedly restart. |
| **`Remove-VMwareStaleSnapshot`** | Action | Removes VM snapshots older than `-MinAgeDays` (default `7`) while automatically skipping active backup appliance snapshots (`Veeam`, `Rubrik`, `Cohesity`, `Zerto`, `Commvault`). |
| **`Enter-VMwareHostMaintenanceSafe`** | Action | Checks VMs on an ESXi host for mounted CD/DVD ISOs that block vMotion, optionally disconnects them (`-DisconnectMountedIso`), and places the host into Maintenance Mode with vSAN data migration mode support. |

---

### 3. Microsoft Azure (4 Cmdlets)

| Cmdlet | Category | Description |
| :--- | :---: | :--- |
| **`Get-AzOrphanedResourceReport`** | Reporting | Scans subscriptions for unattached Managed Disks, unassociated Public IPs, unattached NICs, and empty Resource Groups (with `-ExcludeTagName 'DoNotDelete'` support). |
| **`Get-AzVMBackupAndStatusReport`** | Reporting | Reports Azure VM runtime power states, sizes, OS types, and whether each VM is protected by an Azure Recovery Services Vault backup policy. |
| **`Set-AzVMPowerStateBatch`** | Action | Bulk starts, deallocates (`StopDeallocate`), or restarts Azure VMs filtered by `-ResourceGroupName` or `-TagName` / `-TagValue`, with `-NoWait` async support. |
| **`Remove-AzOrphanedDisk`** | Action | Deletes unattached Azure Managed Disks with an optional `-CreateSnapshotFirst` switch that creates an incremental safety snapshot prior to deletion. |

---

### 4. Local Repository & Reporting Utilities (2 Cmdlets)

| Cmdlet | Category | Description |
| :--- | :---: | :--- |
| **`Publish-ToolkitToLocalRepo`** | Action | Creates and registers a local directory or SMB share as a trusted `PSResourceRepository` (or `PSRepository`) and publishes `SysAdminToolkit` as a `.nupkg` package for on-demand installation. |
| **`Export-ToolkitReport`** | Reporting | Pipeline-ready exporter that converts output from any `Get-*` cmdlet into a styled dark-theme HTML dashboard report, CSV, or JSON file. |

---

## Installation & Local Repository Setup

### Option 1: Publish to a Local Repository & Install On Demand (Recommended)

```powershell
# 1. Clone the repository
git clone https://github.com/chadrothermel-dev/SysAdminToolkit.git
cd SysAdminToolkit

# 2. Import the module from source once
Import-Module .\SysAdminToolkit\SysAdminToolkit.psd1 -Force

# 3. Publish SysAdminToolkit to a local directory or SMB network share
Publish-ToolkitToLocalRepo -RepositoryPath "C:\LocalPSRepo" -RepositoryName "LocalSysAdminRepo" -Verbose

# 4. Install the module whenever you need it (PowerShell 7+ / PSResourceGet)
Install-PSResource -Name SysAdminToolkit -Repository LocalSysAdminRepo -Scope CurrentUser

# Or using PowerShellGet (Windows PowerShell 5.1):
Install-Module -Name SysAdminToolkit -Repository LocalSysAdminRepo -Scope CurrentUser
```

### Option 2: Direct Import

```powershell
Import-Module .\SysAdminToolkit\SysAdminToolkit.psd1 -Force
Get-Command -Module SysAdminToolkit
```

---

## Usage Examples

### Windows Server & Active Directory

```powershell
# Generate an HTML health dashboard across multiple Windows servers
"srv-dc01", "srv-sql01", "srv-app01" |
    Get-WinServerHealthReport |
    Export-ToolkitReport -OutputPath "C:\Reports\WinHealth.html" -ReportTitle "Windows Server Health Audit"

# Check for certificates expiring within 45 days
Get-WinCertificateExpiryReport -ComputerName "srv-iis01", "srv-adfs01" -ExpiringWithinDays 45

# Hunt unexpected reboots, service crashes, and AD lockouts over the past 24 hours
Get-WinCriticalEventReport -ComputerName "srv-dc01" -Hours 24 -IncludeSecurityEvents

# Preview restarting stopped Automatic services
Repair-WinStoppedAutoService -ComputerName "srv-app01" -WhatIf

# Unlock all currently locked-out AD user accounts against the PDC Emulator
Unlock-WinADAccountSafe -AllLockedOut -Verbose

# Preview disabling AD accounts inactive for 90+ days (privileges & specified accounts auto-excluded)
Disable-WinADStaleAccount -InactiveDays 90 -ExcludeSamAccountName "svc-backup", "adm-breakglass" -WhatIf
```

### VMware vSphere (PowerCLI)

```powershell
Connect-VIServer -Server "vcenter.corp.local"

# Audit ESXi Lockdown Mode, Exception Users, SSH, ESXi Shell, NTP, and Syslog across a cluster
Get-VMwareHostSecurityAudit -ClusterName "Prod-Cluster01" |
    Export-ToolkitReport -OutputPath "C:\Reports\ESXiSecurity.html"

# Enable Normal Lockdown Mode across a cluster and add a backup service account to Exception Users
Set-VMwareHostLockdownMode -ClusterName "Prod-Cluster01" -LockdownState Normal -ExceptionUsersToAdd "svc-veeam" -WhatIf

# Disable Lockdown Mode and start SSH on a single host for emergency troubleshooting
Set-VMwareHostLockdownMode -VMHostName "esxi01.corp.local" -LockdownState Disabled
Set-VMwareHostServiceHardening -VMHostName "esxi01.corp.local" -ServiceKey "TSM-SSH" -State Start

# Stop SSH and set startup policy to 'off' across the cluster when finished
Set-VMwareHostServiceHardening -ClusterName "Prod-Cluster01" -ServiceKey "TSM-SSH" -State Stop -StartupPolicy off

# Evacuate a host into Maintenance Mode, automatically disconnecting VM CD/DVD ISO mounts
Enter-VMwareHostMaintenanceSafe -VMHostName "esxi01.corp.local" -DisconnectMountedIso -WhatIf
```

### Microsoft Azure

```powershell
Connect-AzAccount

# Find unattached Managed Disks, Public IPs, NICs, and empty Resource Groups
Get-AzOrphanedResourceReport | Export-ToolkitReport -OutputPath "C:\Reports\AzureOrphans.html"

# Snapshot and delete unattached Managed Disks (with -WhatIf preview)
Get-AzOrphanedResourceReport |
    Where-Object ResourceType -eq 'ManagedDisk' |
    Remove-AzOrphanedDisk -CreateSnapshotFirst -WhatIf

# Deallocate all Dev VMs asynchronously after hours
Set-AzVMPowerStateBatch -Action StopDeallocate -TagName "Environment" -TagValue "Dev" -NoWait -WhatIf
```

---

## Running Unit Tests

```powershell
Invoke-Pester -Path .\Tests\SysAdminToolkit.Tests.ps1 -Output Detailed
```
