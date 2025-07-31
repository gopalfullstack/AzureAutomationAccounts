param(
    [string]$ResourceGroupName = "Prod-RG",
    [string]$Location = "EastUS"
)

function Connect-ProdAzure {
    Write-Output "Authenticating using Service Principal..."
    $spCreds = Get-Content "C:\GopalAzureAutomation\Secure\AzSP.json" | ConvertFrom-Json
    $securePassword = ConvertTo-SecureString $spCreds.ClientSecret -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($spCreds.ApplicationId, $securePassword)
    Connect-AzAccount -ServicePrincipal -Tenant $spCreds.TenantId -Credential $cred | Out-Null
    Set-AzContext -Subscription $spCreds.SubscriptionId | Out-Null
    Write-Output "Authentication successful (headless)."
}

function Create-ResourceGroup($name, $location) {
    Write-Output "Creating Resource Group '$name' in '$location'..."
    if (-not (Get-AzResourceGroup -Name $name -ErrorAction SilentlyContinue)) {
        New-AzResourceGroup -Name $name -Location $location | Out-Null
        Write-Output "Resource Group '$name' created successfully."
    } else {
        Write-Output "Resource Group '$name' already exists."
    }
}

# Execution
Connect-ProdAzure
Create-ResourceGroup -name $ResourceGroupName -location $Location
Write-Output "Script completed."
