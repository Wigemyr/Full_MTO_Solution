# accessPackageWithPIMGroup.ps1 🚀

**Automates the onboarding of guest users, creation of PIM-enabled groups, and access packages in Microsoft Entra (Azure AD)**

---

## 📖 Overview

This script simplifies administrative tasks by automating the following:

1. ✅ **Inviting guest users** based on a provided CSV file.
2. ✅ **Creating a Privileged Identity Management (PIM)-enabled group** for assigning the Security Administrator role.
3. ✅ **Setting up an Access Package Catalog and Access Package** in Microsoft Entra Entitlement Management.
4. ✅ **Creating an auto-assignment policy** based on dynamic group membership rules using the employeeId attribute.

---

## 📋 Prerequisites

Before running this script, ensure:

- **PowerShell 7 or higher** is installed.
  - [Download PowerShell 7](https://github.com/PowerShell/PowerShell/releases)
- **Run as Administrator** (elevated permissions).
- **Execution policy** is set to allow unsigned scripts (recommended: `Bypass` or `Unrestricted`).
- Necessary permissions in Microsoft Entra:
  - Ability to manage users, groups, and entitlement management resources.
  - Ability to create and consent to App Registrations and assign Microsoft Graph permissions.

---

## 🔧 CSV File Structure

This CSV file will contain all the users you want to invite into your Entra ID.  
Your CSV file (`guestInvitation.csv`) must contain the following columns:  

| DisplayName         | Email                              |
|---------------------|------------------------------------|
| FirstName LastName  | FirstLast@example.com              |
| Testy McTestface    | testy.mctestface@contoso.com       |

**Example CSV:**
```csv
DisplayName,Email
FirstName LastName,FirstLast@example.com
Testy McTestface,testy.mctestface@contoso.com
```
Make sure to remove the test users in the sample CSV.
Ensure there are no empty lines or additional unnecessary columns.

---

## 🚦 How to Run

### Usage:
```powershell
pwsh ./accessPackageWithPIMGroup.ps1 -pathToCSV "./guestInvitation.csv"
```

**Parameters:**
- `-pathToCSV`: The path to the CSV file containing guest users' details.

---

## 🔑 Variables Section

The script uses the following variables, which can be customized in the **Variables Section** of the script:

### Group-Related Variables
- **`$groupName`**: Name for the PIM-enabled group (default: `"PIM - Security Admin Group"`).
- **`$groupDescription`**: Description for the group (default: `"PIM-enabled group for Security Administrator role assignment"`).
- **`$roleDisplayName`**: Role to be assigned to the group (default: `"Security Administrator"`).

### Access Package-Related Variables
- **`$catalogName`**: Name for the access package catalog (default: `"Test Catalog"`).
- **`$accessPackageName`**: Name for the access package (default: `"Test Access Package"`).
- **`$accessPackageDescription`**: Description for the access package (default: `"Test Access Package created via PowerShell"`).

### Auto-Assignment Policy Variables
- **`$autoPolicyName`**: Name for the auto-assignment policy (default: `"Test Auto-Assignment Policy"`).
- **`$autoPolicyDescription`**: Description for the auto-assignment policy (default: `"Auto-assignment policy for employeeId"`).
- **`$employeeIdFilter`**: Dynamic membership rule for the policy (default: `'(user.employeeId -eq "n38fy345gf54")'`).
- **`$policyDescription`**: Description for the membership rule (default: `"Auto-assignment policy for employeeId filter"`).

### Retry Configuration
- **`$retryCount`**: Number of retry attempts for operations (default: `5`).
- **`$retryDelaySeconds`**: Delay between retries in seconds (default: `5`).

---

## ⚠️ Important Information About Guest Invitations

After running the script, **guest users will receive an invitation email**. It is critical that these invitations are accepted by the recipients. 

### Why is this important?
- Accepting the invitation is required for the guest users to gain access to the resources and functionality provided by the access package.
- Once the invitation is accepted, users will be able to see and access the assigned resources in their **My Apps portal**:  
  [https://myapplications.microsoft.com](https://myapplications.microsoft.com)

### Expected Behavior
- It may take up to **1 hour** for the access package assignment to apply after the invitation is accepted.
- This is normal and does not require troubleshooting.

---

## 🔑 Steps Automated by the Script

Upon execution, the script performs:

1. **PowerShell Version Check**
   - Confirms PowerShell 7+.

2. **Module Installation**
   - Installs required modules (`Microsoft.Graph`).

3. **Microsoft Graph Authentication**
   - Authenticates and connects with appropriate scopes.

4. **Guest User Invitations**
   - Sends invitations based on provided CSV.

5. **PIM Group Management**
   - Creates or reuses a PIM-enabled group (`Security Administrator` role).

6. **Access Package Setup**
   - Creates Access Package Catalog and Access Package.

7. **Resource and Role Assignment**
   - Adds the created group as a resource with assigned roles.

8. **Auto-assignment Policy Creation**
   - Configures automatic user assignment using `employeeId`.

---

## 🛑 Important Notes

- **Execution Policy:**  
  Script is unsigned; ensure your execution policy permits running such scripts:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
  ```
- **Admin Consent:**  
  Initial execution might prompt for admin consent for Microsoft Graph permissions.
- **Internal Use Only:**  
  This script is intended strictly for administrative tasks within your tenant.

---

## ⚠️ Troubleshooting

| Issue                           | Solution                                                                                                                     |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| Script fails on version check   | Ensure PowerShell 7+ is installed and you're using `pwsh.exe` instead of `powershell.exe`.                                   |
| Module installation failure     | Verify your internet connectivity and permissions. Manually install via `Install-Module Microsoft.Graph -Scope CurrentUser`. |
| Authentication issues           | Confirm your account has sufficient privileges in Microsoft Entra.                                                           |

---

## 📌 Microsoft Docs References

- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview)
- [Privileged Identity Management](https://learn.microsoft.com/en-us/entra/identity/privileged-identity-management/pim-configure)
- [Entitlement Management (Access Packages)](https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-overview)