# Automating Access Package Creation and Azure Lighthouse Onboarding

This project spans two separate repositories:

- **Access Package Script Repository:** [Link to Access Package Script Repository](<ACCESS_PACKAGE_REPO_URL>)
- **Azure Lighthouse Onboarding Script Repository:** [Link to Lighthouse Script Repository](<LIGHTHOUSE_REPO_URL>)

These scripts are used to onboard external tenants and users in a secure and scalable manner by combining Microsoft Entra Entitlement Management and Azure Lighthouse.

---

## 🧭 Workflow Overview

1. **Run `accessPackageWithPIMGroup.ps1`** (from the Access Package repo)  
   This script creates:
   - An Entra catalog and access package
   - A PIM-enabled group that grants a directory role
   - An auto-assignment policy for users listed in a provided CSV

2. **Manually Create an Azure AD Group**  
   This group will be used to assign RBAC roles in target subscriptions via Azure Lighthouse.

3. **Run `onboarding_Lighthouse.ps1`** (from the Lighthouse repo)  
   This script deploys an ARM template to register the management tenant as a service provider and assign roles to the Azure AD group created in step 2.

---

## 📋 Prerequisites

### PowerShell
- PowerShell 7 (`pwsh.exe`)

### Required Modules
The following modules will be installed automatically by the scripts if not already present:

| Script | Modules Required |
|--------|------------------|
| `accessPackageWithPIMGroup.ps1` | `Microsoft.Graph` |
| `onboarding_Lighthouse.ps1`     | `Az.Accounts`, `Az.Resources`, `Az.ManagedServices` |

### Required Roles
| Task | Required Role |
|------|----------------|
| Run access package script         | Global Administrator (in management tenant) |
| Run onboarding script             | Owner (on target subscriptions) + Global Administrator (in tenant where subscription is present (customer-tenant)) |

---

## 🛠️ Setup Instructions

### Step 1: Run the Access Package Script

Before running the script, make sure to **manually edit `guestInvitation.csv`** to include the management tenant users you want to invite into the **customer (underlying) tenant**. These users will be assigned roles via the access package.


> 📂 Navigate to the folder where the `accessPackageWithPIMGroup.ps1` script is located before running the command below.

```powershell
cd ./AccessPackageWithPIMGroup
./accessPackageWithPIMGroup.ps1 -pathToCSV "C:\path\to\guests.csv"
```

This step creates the necessary access package and PIM-enabled group.

---

### Step 2: Manually Create a Group in Azure AD

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Entra ID > Groups**
3. Create a **Security** group with:
   - A meaningful name (e.g., `LighthouseContributors`)
   - Membership type: Assigned or Dynamic
4. Add necessary members (these are the users who will manage the customer subscriptions)
5. Record:
   - The **Display Name**
   - The **Object ID**

---

### Step 3: Run the Azure Lighthouse Onboarding Script

> 📂 Navigate to the folder where the `onboarding_Lighthouse.ps1` script is located before running the command below.

Before running the script, open `onboarding_Lighthouse.ps1` and update the following variables:

```powershell
$pocGroupName = "<DISPLAY_NAME_OF_AZURE_AD_GROUP>"
$pocGroupRole = "<RBAC_ROLE>" # e.g., Contributor
```

Then execute:

```powershell
cd ./LighthouseOnboarding
./onboarding_Lighthouse.ps1
```

This script will:
- Install missing Azure modules
- Prompt you to sign in
- Retrieve eligible subscriptions
- Deploy the ARM template (`subscription.json`) using your settings in `subscription.parameters.json`

---

## 📁 Files Overview

| File | Description |
|------|-------------|
| `accessPackageWithPIMGroup.ps1` | Creates an access package with PIM-enabled group |
| `onboarding_Lighthouse.ps1`     | Deploys Azure Lighthouse registration |
| `subscription.json`             | ARM template for Lighthouse onboarding |
| `subscription.parameters.json`  | Parameters for customizing the deployment |

> 📝 Be sure to update placeholders in `subscription.parameters.json`:
> - Placeholders are written as "<>"

---

## ✅ Example

```powershell
$pocGroupName = "LighthouseContributors"
$pocGroupRole = "Contributor"
```

Change these variables in the script to match the group you created.

---

## 🔗 References

- [Azure Lighthouse Documentation](https://learn.microsoft.com/azure/lighthouse/)
- [Microsoft Graph PowerShell](https://learn.microsoft.com/powershell/microsoftgraph/overview)
