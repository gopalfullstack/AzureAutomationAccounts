Azure Automation Accounts – Scripts & Runbooks
This repository contains production‑ready PowerShell scripts and runbooks for automating tasks in Microsoft Azure using Azure Automation Accounts.

Overview
Azure Automation Accounts enable you to:

Automate VM provisioning, management, and cleanup

Run PowerShell or Python scripts in a serverless environment

Integrate with Azure services securely using Managed Identity

Schedule tasks for cost optimization, monitoring, and infrastructure management

This repo serves as a central collection of reusable scripts for DevOps engineers and cloud administrators.

Included Scripts
Create‑WindowsVM.ps1
Deploys a Windows VM with:

Public IP, VNet, Subnet, NIC

NSG with RDP (3389) access pre‑configured

Trusted Launch support (auto‑switches region/size if unsupported)

Works with Managed Identity (in Automation) or Service Principal (locally)

Planned additions:

Cost optimization scripts

Resource cleanup automation

Scheduling & monitoring scripts

How to Use
1. Run Locally
Clone the repository:


git clone https://github.com/gopalfullstack/AzureAutomationAccounts.git
cd AzureAutomationAccounts
Update Secure/AzSP.json with your Service Principal credentials:

json
{
  "TenantId": "<Tenant-ID>",
  "ApplicationId": "<App-ID>",
  "ClientSecret": "<Secret>",
  "SubscriptionId": "<Subscription-ID>"
}
Run the script:


pwsh .\Scripts\Create-WindowsVM.ps1 -ResourceGroup "DevRG" -Location "WestEurope" -VmName "AutoVM01" -VmSize "Standard_D2s_v3" -EnableTrustedLaunch
2. Run in Azure Automation
Create an Automation Account in the Azure Portal

Enable System‑Assigned Managed Identity

Import this script as a Runbook

Grant the Automation Account Contributor role on your subscription/resource group

Start the Runbook with parameters

Security
No secrets stored in GitHub – The Secure/ folder is git‑ignored

Use Azure Key Vault or GitHub Actions Secrets for credentials in CI/CD

Roadmap
 Add GitHub Actions workflow for CI/CD automation

 More reusable runbooks for cost optimization & auto‑scaling

 Integration with Azure Key Vault for secure secret management

 Scheduled automation samples

Contributing
Contributions are welcome!

Open an issue for suggestions or feature requests

Submit a pull request for new scripts or improvements

**Author
👤 Gopal Meena
Senior Azure DevOps & Cloud Engineer
LinkedIn**
