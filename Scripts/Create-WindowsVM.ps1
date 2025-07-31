<#
.SYNOPSIS
    Create a Windows VM using Azure Automation (Managed Identity) or Local (Service Principal).
.DESCRIPTION
    - Works in Azure Automation (Managed Identity) or locally with Service Principal.
    - Supports Trusted Launch. If unsupported, auto-switches to a supported size/region.
    - Adds NSG with RDP (3389) inbound rule for VM access.
    - If no Trusted Launch support is found, falls back to standard VM.
#>

param(
    [string]$ResourceGroup = "AutoRG",
    [string]$Location = "WestEurope",
    [string]$VmName = "AutoVM01",
    [string]$VmSize = "Standard_D2s_v3",
    [string]$AdminUsername = "azureuser",
    [string]$AdminPassword = "StrongP@ssw0rd123!",
    [string]$Publisher = "MicrosoftWindowsServer",
    [string]$Offer = "WindowsServer",
    [string]$Sku = "2022-datacenter-azure-edition",
    [ValidateSet("Basic","Standard")] [string]$PublicIpSku = "Standard",
    [ValidateSet("Static","Dynamic")] [string]$PublicIpAllocation = "Static",
    [string]$PublicIpName = "",
    [string]$VnetName = "",
    [string]$SubnetName = "",
    [string]$NicName = "",
    [string]$NsgName = "",
    [string]$BootDiagStorageUri = "",
    [switch]$EnableTrustedLaunch
)

if (-not $PublicIpName) { $PublicIpName = "$VmName-pip" }
if (-not $VnetName) { $VnetName = "$VmName-vnet" }
if (-not $SubnetName) { $SubnetName = "$VmName-subnet" }
if (-not $NicName) { $NicName = "$VmName-nic" }
if (-not $NsgName) { $NsgName = "$VmName-nsg" }

Update-AzConfig -DisplayBreakingChangeWarning $false -DisplayRegionIdentified $false | Out-Null

function Log($msg) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Output "[$timestamp] $msg"
}

function Connect-ProdAzure {
    Log "Authenticating..."
    try {
        if ($env:AUTOMATION_ASSET_ACCOUNTID) {
            Log "Detected: Azure Automation - Using Managed Identity"
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        } else {
            Log "Detected: Local VS Code - Using Service Principal"
            $spCreds = Get-Content "C:\GopalAzureAutomation\Secure\AzSP.json" | ConvertFrom-Json
            $securePassword = ConvertTo-SecureString $spCreds.ClientSecret -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($spCreds.ApplicationId, $securePassword)
            Connect-AzAccount -ServicePrincipal -Tenant $spCreds.TenantId -Credential $cred -ErrorAction Stop | Out-Null
            Set-AzContext -Subscription $spCreds.SubscriptionId -ErrorAction Stop | Out-Null
        }
        Log "Authentication successful."
    } catch { throw "Authentication failed: $($_.Exception.Message)" }
}

function Ensure-TrustedLaunchSupport {
    param(
        [string]$CurrentLocation,
        [string]$CurrentSize
    )

    $sku = Get-AzComputeResourceSku -Location $CurrentLocation `
        | Where-Object { $_.ResourceType -eq "virtualMachines" -and $_.Name -eq $CurrentSize }
    $trusted = $sku.Capabilities | Where-Object { $_.Name -eq "TrustedLaunchSupported" -and $_.Value -eq "True" }

    if ($trusted) {
        Log "Trusted Launch supported for $CurrentSize in $CurrentLocation."
        return @{ Location = $CurrentLocation; Size = $CurrentSize }
    }

    Log "Trusted Launch NOT supported for $CurrentSize in $CurrentLocation. Searching alternatives..."
    $all = Get-AzComputeResourceSku | Where-Object { $_.ResourceType -eq "virtualMachines" -and $_.Name -like "Standard_D2s_*" }
    $supported = foreach ($item in $all) {
        $cap = $item.Capabilities | Where-Object { $_.Name -eq "TrustedLaunchSupported" -and $_.Value -eq "True" }
        if ($cap) { $item }
    }
    $recommend = $supported | Select-Object -First 1

    if (-not $recommend) {
        Log "No Trusted Launch–supported VM sizes found. Proceeding without Trusted Launch."
        return @{ Location = $CurrentLocation; Size = $CurrentSize; SkipTrusted = $true }
    }

    Log "Auto-switching to $($recommend.Name) in $($recommend.Locations[0]) for Trusted Launch."
    return @{ Location = $recommend.Locations[0]; Size = $recommend.Name }
}

function Create-WindowsVM {
    try {
        # Auto-switch if needed
        if ($EnableTrustedLaunch) {
            $newConfig = Ensure-TrustedLaunchSupport -CurrentLocation $Location -CurrentSize $VmSize
            $Location = $newConfig.Location
            $VmSize = $newConfig.Size
            if ($newConfig.SkipTrusted) {
                Log "Trusted Launch will be disabled (unsupported combination)."
                $EnableTrustedLaunch = $false
            }
        }

        # Resource Group
        Log "Ensuring Resource Group '$ResourceGroup'..."
        if (-not (Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue)) {
            New-AzResourceGroup -Name $ResourceGroup -Location $Location -ErrorAction Stop | Out-Null
            Log "Resource Group created."
        }

        # Public IP
        if ($PublicIpSku -eq "Standard" -and $PublicIpAllocation -ne "Static") { $PublicIpAllocation = "Static" }
        Log "Ensuring Public IP '$PublicIpName'..."
        $publicIp = Get-AzPublicIpAddress -Name $PublicIpName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
        if (-not $publicIp) {
            $publicIp = New-AzPublicIpAddress -Name $PublicIpName -ResourceGroupName $ResourceGroup -Location $Location -AllocationMethod $PublicIpAllocation -Sku $PublicIpSku -ErrorAction Stop
        }

        # VNet/Subnet
        Log "Ensuring VNet '$VnetName' and Subnet '$SubnetName'..."
        $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
        if (-not $vnet) {
            $vnet = New-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroup -Location $Location -AddressPrefix "10.0.0.0/16" -ErrorAction Stop
            Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -AddressPrefix "10.0.0.0/24" | Out-Null
            $vnet | Set-AzVirtualNetwork | Out-Null
            Start-Sleep -Seconds 5
        } else {
            $subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
            if (-not $subnet) {
                Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -AddressPrefix "10.0.0.0/24" | Out-Null
                $vnet | Set-AzVirtualNetwork | Out-Null
                Start-Sleep -Seconds 5
            }
        }
        $vnet = Get-AzVirtualNetwork -Name $VnetName -ResourceGroupName $ResourceGroup -ErrorAction Stop
        $subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -ErrorAction Stop

        # NSG with RDP
        Log "Ensuring NSG '$NsgName' with RDP rule..."
        $nsg = Get-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
        if (-not $nsg) {
            $nsg = New-AzNetworkSecurityGroup -Name $NsgName -ResourceGroupName $ResourceGroup -Location $Location
            $nsg | Add-AzNetworkSecurityRuleConfig -Name "Allow-RDP" -Description "Allow RDP" -Access Allow -Protocol Tcp -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 | Set-AzNetworkSecurityGroup
        }

        # NIC
        Log "Ensuring NIC '$NicName'..."
        $nic = Get-AzNetworkInterface -Name $NicName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
        if (-not $nic) {
            $nic = New-AzNetworkInterface -Name $NicName -ResourceGroupName $ResourceGroup -Location $Location -SubnetId $subnet.Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id -ErrorAction Stop
        } else {
            $nic.NetworkSecurityGroup = $nsg
            $nic | Set-AzNetworkInterface
        }

        # VM Config
        Log "Preparing VM '$VmName'..."
        $securePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($AdminUsername, $securePassword)
        $vmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize |
            Set-AzVMOperatingSystem -Windows -ComputerName $VmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate |
            Set-AzVMSourceImage -PublisherName $Publisher -Offer $Offer -Skus $Sku -Version "latest" |
            Add-AzVMNetworkInterface -Id $nic.Id

        if ($EnableTrustedLaunch) {
            $vmConfig.SecurityProfile = @{ SecurityType = "TrustedLaunch" }
        }

        if ($BootDiagStorageUri -ne "") {
            $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable -ResourceGroupName $ResourceGroup -StorageAccountUri $BootDiagStorageUri
        }

        # Create VM
        Log "Creating VM in $Location with size $VmSize..."
        New-AzVM -ResourceGroupName $ResourceGroup -Location $Location -VM $vmConfig -ErrorAction Stop
        Log "VM created successfully and RDP is enabled."
    } catch { throw "VM creation failed: $($_.Exception.Message)" }
}

Connect-ProdAzure
Create-WindowsVM
Log "Script completed successfully."
