# Load Modules
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\Log\Log.psd1")
Import-Module ((Split-Path $PSScriptRoot -Parent) + "\UpdateVmssInstances\UpdateVmssInstances.psd1")
function BackendPoolMigration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $BasicLoadBalancer,
        [Parameter(Mandatory = $True)][Microsoft.Azure.Commands.Network.Models.PSLoadBalancer] $StdLoadBalancer
    )
    log -Message "[BackendPoolMigration] Initiating Backend Pool Migration"
    log -Message "[BackendPoolMigration] Looping all BackendAddressPools"
    foreach ($basicBackendAddressPool in $BasicLoadBalancer.BackendAddressPools) {
        log -Message "[BackendPoolMigration] Adding BackendAddressPool $($basicBackendAddressPool.Name)"

        try {
            $ErrorActionPreference = 'Stop'
            $StdLoadBalancer | Add-AzLoadBalancerBackendAddressPoolConfig -Name $basicBackendAddressPool.Name | Set-AzLoadBalancer > $null
        }
        catch {
            $message = @"
                [BackendPoolMigration] An error occured when adding a backend pool to the new Standard LB '$StdLoadBalancerName'. To recover
                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup 
                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
            log 'Error' $message
            Exit
        }

        log -Message "[BackendPoolMigration] Adding Standard Load Balancer back to the VMSS"
        $vmssIds = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { $_.split("virtualMachines")[0] } | Select-Object -Unique
        $BackendIpConfigurationName = $BasicLoadBalancer.BackendAddressPools.BackendIpConfigurations.id | Foreach-Object { $_.split("/")[-1] } | Select-Object -Unique
        foreach ($vmssId in $vmssIds) {
            $vmssName = $vmssId.split("/")[8]
            $vmssRg = $vmssId.Split('/')[4]

            try {
                $ErrorActionPreference = 'Stop'
                $vmss = Get-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName
            }
            catch {
                $message = @"
                    [BackendPoolMigration] An error occured when calling 'Get-AzVmss -ResourceGroupName '$vmssRg' -VMScaleSetName '$vmssName'. To recover
                    address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup 
                    State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
                log 'Error' $message
                Exit
            }

            log -Message "[BackendPoolMigration] Adding BackendAddressPool to VMSS $($vmss.Name)"
            foreach ($networkInterfaceConfiguration in $vmss.VirtualMachineProfile.NetworkProfile.NetworkInterfaceConfigurations) {
                $genericListSubResource = New-Object System.Collections.Generic.List[Microsoft.Azure.Management.Compute.Models.SubResource]
                foreach ($ipConfiguration in $networkInterfaceConfiguration.IpConfigurations) {
                    if ($ipConfiguration.Name -contains $BackendIpConfigurationName) {
                        try {
                            $subResource = New-Object Microsoft.Azure.Management.Compute.Models.SubResource
                            $subResource.Id = ($StdLoadBalancer.BackendAddressPools | Where-Object { $_.Name -eq $basicBackendAddressPool.Name }).Id
                            $genericListSubResource.Add($subResource)
                        }
                        catch {
                            $message = @"
                                [BackendPoolMigration] An error occured creating a new VMSS IP Config. To recover
                                address the following error, and try again specifying the -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup 
                                State file located either in this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
                            log 'Error' $message
                            Exit
                        }
                    }
                }
                $ipConfiguration.LoadBalancerBackendAddressPools = $genericListSubResource
            }
            log -Message "[BackendPoolMigration] Saving VMSS $($vmss.Name)"

            try {
                $ErrorActionPreference = 'Stop'
                Update-AzVmss -ResourceGroupName $vmssRg -VMScaleSetName $vmssName -VirtualMachineScaleSet $vmss > $null
            }
            catch {
                $message = @"
                    [BackendPoolMigration] An error occured when attempting to update VMSS network config new Standard 
                    LB backend pool membership. To recover address the following error, and try again specifying the 
                    -FailedMigrationRetryFilePath parameter and Basic Load Balancer backup State file located either in 
                    this directory or the directory specified with -RecoveryBackupPath. `nError message: $_
"@
                log 'Error' $message
                Exit
            }

            log -Message "[BackendPoolMigration] Updating VMSS Instances $($vmss.Name)"
            UpdateVmssInstances -vmss $vmss
        }
    }
    #log -Message "[BackendPoolMigration] StackTrace $($StackTrace)" -Severity "Debug"
    log -Message "[BackendPoolMigration] Backend Pool Migration Completed"
}

Export-ModuleMember -Function BackendPoolMigration