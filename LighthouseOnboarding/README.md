# Azure Lighthouse Onboarding Script

This PowerShell script automates the onboarding of Azure subscriptions to Azure Lighthouse. It follows Azure best practices to ensure a smooth and secure onboarding process. The script performs various checks, deploys Azure Resource Manager (ARM) templates, and verifies the onboarding status.

---

## Features

1. **PowerShell Version Check**  
   Ensures the script is executed in PowerShell 7 or later.

2. **Module Validation and Installation**  
   Verifies that required Azure PowerShell modules (`Az.Accounts`, `Az.Resources`, `Az.ManagedServices`) are installed. If not, it installs them automatically.

3. **Azure Sign-In**  
   Prompts the user to sign in to Azure if no active session is detected.

4. **Global Administrator Role Check**  
   Confirms whether the signed-in user has the Global Administrator role in Azure Active Directory (Entra ID). If not, the user is prompted to proceed or abort.

5. **Owner Role Validation on Subscriptions**  
   Checks if the user has the `Owner` role on all subscriptions. Subscriptions without the required role are flagged, and the user is prompted to proceed or abort.

6. **Azure Lighthouse Onboarding**  
   - Loops through enabled subscriptions.
   - Deploys an ARM template for Azure Lighthouse onboarding.
   - Verifies the onboarding status and outputs detailed results.

7. **Deployment Details**  
   Displays deployment details, including provisioning state, deployment name, location, and timestamp.

8. **Final Success Message**  
   Summarizes the onboarding process and confirms completion.

---

## Prerequisites

- **PowerShell 7 or Later**  
  Ensure you are running PowerShell 7+ (`pwsh.exe`).

- **Azure PowerShell Modules**  
  The script requires the following modules:
  - `Az.Accounts`
  - `Az.Resources`
  - `Az.ManagedServices`

- **Azure Permissions**  
  - Global Administrator role in Azure Active Directory (optional but recommended).
  - Owner role on the subscriptions to be onboarded.

---

## Parameters

The script uses the following parameters, which can be customized to suit your environment:

- **ARM Template File**:  
  Path to the ARM template file for Azure Lighthouse onboarding.  
  Default: `.\templates\subscription.json`

- **ARM Parameters File**:  
  Path to the parameters file for the ARM template.  
  Default: `.\templates\subscription.parameters.json`

- **Azure Region**:  
  The region where the resources will be deployed.  
  Default: `norwayeast`

- **PoC Group Object ID**:  
  Object ID of the PoC group in Azure Active Directory.  
  Default: `e3dbb341-c647-4823-a85e-7a7f40f1de62`

---

## How to Use

1. **Clone the Repository**  
   Clone or download the script to your local machine.

2. **Fix variables in the Variables-section**
   Change the variables to suit your needs before running script.   

3. **Run the Script**  
   Open PowerShell 7 and execute the script:

   ```powershell
   ./onboarding_Lighthouse.ps1
   ```

4. **Follow the Prompts**  
   - Sign in to Azure when prompted.
   - Confirm whether to proceed if you lack the Global Administrator or Owner role.

5. **Monitor the Output**  
   - The script will display progress and results for each step.
   - Deployment details and verification results will be shown for each subscription.

---

## Offboarding

If you would like to offboard subscriptions from Azure Lighthouse, use the **offboarding script** provided in this repository. The offboarding script will remove the Azure Lighthouse delegations for the specified subscriptions.

---


## Script Workflow

1. **Environment Validation**  
   - Checks PowerShell version.
   - Ensures required modules are installed.

2. **Azure Sign-In**  
   - Prompts the user to sign in if no active session is detected.

3. **Role Validation**  
   - Checks for Global Administrator and Owner roles.
   - Prompts the user to proceed or abort if roles are missing.

4. **Subscription Processing**  
   - Loops through enabled subscriptions.
   - Deploys the ARM template for Azure Lighthouse onboarding.

5. **Verification**  
   - Verifies the onboarding status for each subscription.
   - Outputs detailed results, including tenant and role information.

6. **Final Summary**  
   - Displays a success message and summarizes the onboarding process.

---

## Example Output

```plaintext
[INFO] PowerShell version 7.3.0 detected. Continuing execution...
[INFO] Module 'Az.Accounts' is already installed.
[INFO] Signing in to Azure...
[SUCCESS] User is a confirmed Global Administrator.
[INFO] Checking role assignments for user: user@domain.com
[SUCCESS] Deployment succeeded (LHO-12345678).
[INFO] Azure Lighthouse onboarding complete!
```

---

## Troubleshooting

- **PowerShell Version Error**:  
  Ensure you are running PowerShell 7 or later. Install it from [PowerShell GitHub](https://github.com/PowerShell/PowerShell).

- **Module Installation Issues**:  
  Run the following command to manually install required modules:

  ```powershell
  Install-Module -Name Az -Scope CurrentUser -AllowClobber -Force
  ```

- **Azure Sign-In Issues**:  
  Ensure you have the correct permissions and are signing in with the appropriate account.

- **Deployment Errors**:  
  Check the ARM template and parameters file for correctness. Ensure the subscription has sufficient permissions.

---

## Best Practices

- Test the script in a non-production environment before running it in production.

---

