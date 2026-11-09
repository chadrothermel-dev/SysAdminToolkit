BeforeAll {
    $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
    $manifestPath = Join-Path -Path $moduleRoot -ChildPath 'SysAdminToolkit\SysAdminToolkit.psd1'
    Import-Module -Name $manifestPath -Force -ErrorAction Stop
}

Describe 'SysAdminToolkit Module Manifest & Exports' {
    It 'Should have a valid module manifest at version 1.1.0' {
        $manifestPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'SysAdminToolkit\SysAdminToolkit.psd1'
        $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        $manifest.Name | Should -Be 'SysAdminToolkit'
        $manifest.Version.ToString() | Should -Be '1.1.0'
    }

    It 'Should export all 26 expected public functions' {
        $exported = (Get-Module -Name 'SysAdminToolkit').ExportedFunctions.Keys
        $exported.Count | Should -Be 26
    }

    It 'Should support -WhatIf (SupportsShouldProcess) on all 13 Action cmdlets' {
        $actionCmdlets = @(
            'Repair-WinStoppedAutoService',
            'Clear-WinTempAndUpdateCache',
            'Unlock-WinADAccountSafe',
            'Disable-WinADStaleAccount',
            'Invoke-WinGPUpdateRemote',
            'Set-AzVMPowerStateBatch',
            'Remove-AzOrphanedDisk',
            'Remove-VMwareStaleSnapshot',
            'Enter-VMwareHostMaintenanceSafe',
            'Set-VMwareHostLockdownMode',
            'Set-VMwareHostServiceHardening',
            'Update-VMwareToolsBatch',
            'Publish-ToolkitToLocalRepo'
        )
        foreach ($cmdName in $actionCmdlets) {
            $cmd = Get-Command -Name $cmdName -Module 'SysAdminToolkit'
            $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue -Because "$cmdName mutates infrastructure state"
            $cmd.Parameters.ContainsKey('Confirm') | Should -BeTrue -Because "$cmdName mutates infrastructure state"
        }
    }

    It 'Should provide Synopsis, Description, and Examples in Comment-Based Help for all 26 exported functions' {
        $exported = (Get-Module -Name 'SysAdminToolkit').ExportedFunctions.Keys
        foreach ($fn in $exported) {
            $help = Get-Help -Name $fn
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "$fn should have a .SYNOPSIS"
            $help.Description | Should -Not -BeNullOrEmpty -Because "$fn should have a .DESCRIPTION"
        }
    }
}
