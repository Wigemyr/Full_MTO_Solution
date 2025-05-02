<#
Author          : Bakken, Anders Wigemyr
Date            : 29-04-2025
Version         : 1.0
Description     : Automates the following steps:
                1. Validates PowerShell version (requires 7+)
                2. Checks and installs required Azure PowerShell modules
                3. Connects to Azure and verifies user roles (Global Administrator and Owner)
                4. Processes enabled subscriptions for Azure Lighthouse onboarding
                5. Deploys Azure Resource Manager (ARM) templates for Lighthouse
                6. Verifies Azure Lighthouse onboarding status
                7. Outputs deployment details and onboarding results

Note            : Requires PowerShell 7+. Must be run with elevated permissions (Run as Administrator).
                  Script is unsigned – adjust execution policy accordingly (e.g., Bypass or Unrestricted).
                  Intended for internal administrative use only.

Script execution: onboarding_Lighthouse.ps1
Attachments     : subscription.json, subscription.parameters.json, offboarding_Lighthouse.ps1
                  
#>



# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────

# General settings
$location       = "norwayeast"                                  # Azure region for deployments - change if needed
$templateFile   = ".\templates\subscription.json"               # Path to ARM template
$paramsFile     = ".\templates\subscription.parameters.json"    # Path to ARM parameters file
$location       = "norwayeast"                                  # Azure region for deployments - change if needed

# Group settings
$pocGroupName   = "<display name of entra id group>"            # Display name of the PoC group
$pocGroupRole   = "<rbac role>"                                 # Role assigned to the PoC group

# Other settings
$requiredRole   = "Owner"                                       # Required role for onboarding - only "Owner" is supported



# ─────────────────────────────────────────────────────────────────────────────
# PowerShell Version Check (Requires 7+)
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                      CHECK POWERSHELL VERSION                      │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] This script requires PowerShell 7 or later." -ForegroundColor Yellow

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "[ERROR] You are running PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Red
    Write-Host "[INFO] Please run this script using PowerShell 7 (e.g. 'pwsh.exe')." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "[SUCCESS] PowerShell version $($PSVersionTable.PSVersion) detected. Continuing execution..." -ForegroundColor Green
}

Start-Sleep -Seconds 2

# ─────────────────────────────────────────────────────────────────────────────
# CHECK & INSTALL REQUIRED MODULES
# ─────────────────────────────────────────────────────────────────────────────


Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                   CHECK & INSTALL REQUIRED MODULES                 │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


# Define the required modules
$requiredModules = @("Az.Accounts", "Az.Resources", "Az.ManagedServices")  # Add required module names here

# List of required modules (defined in variables section)
foreach ($module in $requiredModules) {
    # Check if module is installed
    $moduleInstalled = Get-Module -ListAvailable -Name $module

    if ($moduleInstalled) {
        Write-Host "[INFO] Module '$module' is already installed." -ForegroundColor Green
    } else {
        Write-Host "[INFO] Module '$module' not found. Installing..." -ForegroundColor Yellow

        try {
            Install-Module $module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        } catch {
            Write-Host "[ERROR] Failed to install module '$module': $_" -ForegroundColor Red
            exit 1
        }

        # Verify installation
        $moduleInstalled = Get-Module -ListAvailable -Name $module
        if ($moduleInstalled) {
            Write-Host "[SUCCESS] Module '$module' installed successfully!" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Module '$module' installation did not complete. Please install manually." -ForegroundColor Red
            exit 1
        }
    }
}

Start-Sleep -Seconds 2

# ─────────────────────────────────────────────────────────────────────────────
# SIGNING INTO AZURE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                        SIGNING INTO AZURE                          │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Connect-AzAccount -ErrorAction Stop | Out-Null # Connect to Azure account

Start-Sleep -Seconds 2



# ─────────────────────────────────────────────────────────────────────────────
# CHECK FOR GLOBAL ADMINISTRATOR IN ENTRA ID
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│           CHECKING GLOBAL ADMINISTRATOR ROLE IN ENTRA ID           │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

try {
    # Acquire token for Microsoft Graph, suppress upcoming warning
    $token = (Get-AzAccessToken -ResourceTypeName MSGraph -WarningAction SilentlyContinue).Token
    $headers = @{ Authorization = "Bearer $token" }

    # Query Microsoft Graph for user's directory roles
    $rolesUri = "https://graph.microsoft.com/v1.0/me/memberOf"
    $response = Invoke-RestMethod -Uri $rolesUri -Headers $headers -Method GET

    # Check if Global Administrator role exists
    $isGlobalAdmin = $false

    foreach ($item in $response.value) {
        if ($item.'@odata.type' -eq "#microsoft.graph.directoryRole" -and $item.displayName -eq "Global Administrator") {
            $isGlobalAdmin = $true
            break
        }
    }

    if ($isGlobalAdmin) {
        Write-Host "[SUCCESS] User is a confirmed Global Administrator." -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] User is NOT a Global Administrator." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Do you still wish to proceed onboarding subscriptions? (Y/N)" -ForegroundColor Yellow
        $proceed = Read-Host "Type Y to proceed or N to abort"

        if ($proceed -notin @('Y', 'y')) {
            Write-Host ""
            Write-Host "═════════════════════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host "   ABORTED: User chose not to proceed without Global Administrator rights." -ForegroundColor Red
            Write-Host "═════════════════════════════════════════════════════════════════════════════" -ForegroundColor Red
            exit 1
        }
    }
}
catch {
    Write-Host "[ERROR] Failed to check Global Administrator role: $_" -ForegroundColor Red
    exit 1
}

start-sleep -seconds 2


# ─────────────────────────────────────────────────────────────────────────────
# CHECK FOR OWNER ROLE ON SUBSCRIPTIONS
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                CHECKING OWNER ROLE ON SUBSCRIPTIONS                │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Connect if needed
if (-not (Get-AzContext)) {
    Connect-AzAccount -ErrorAction Stop | Out-Null
}

# Get current signed-in user
$currentContext = Get-AzContext -ErrorAction Stop
$currentUserUpn = $currentContext.Account

Write-Host "[INFO] Checking role assignments for user: $currentUserUpn" -ForegroundColor Yellow

# Required role
$requiredRole = "Owner"

try {
    # Get all subscriptions available
    $subscriptions = Get-AzSubscription -ErrorAction Stop

    # Initialize collections
    $ownerSubs    = @()
    $notOwnerSubs = @()

    foreach ($sub in $subscriptions) {
        # Set context for each subscription without warnings about disabled subscriptions
        Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null

        # Get role assignments for the subscription
        $roleAssignments = Get-AzRoleAssignment -SignInName $currentUserUpn -Scope "/subscriptions/$($sub.Id)" -ErrorAction SilentlyContinue

        $subInfo = [PSCustomObject]@{
            SubscriptionName  = $sub.Name
            SubscriptionId    = $sub.Id
            SubscriptionState = $sub.State
        }

        if ($roleAssignments -and ($roleAssignments.RoleDefinitionName -contains $requiredRole)) {
            $ownerSubs += $subInfo
        }
        else {
            $notOwnerSubs += $subInfo
        }
    }

    # Sort alphabetically
    $ownerSubs    = $ownerSubs    | Sort-Object SubscriptionName
    $notOwnerSubs = $notOwnerSubs | Sort-Object SubscriptionName

    # Define consistent label width
    $labelWidth = 22

    # Output Owner list
    Write-Host ""
    Write-Host "─────────────────────────────────────────────────────────────────────"  -ForegroundColor Gray
    Write-Host " Subscriptions where user HAS 'Owner' role:"                            -ForegroundColor Green
    Write-Host "─────────────────────────────────────────────────────────────────────"  -ForegroundColor Gray

    if ($ownerSubs.Count -gt 0) {
        foreach ($sub in $ownerSubs) {
            Write-Host ("  " + "Subscription Name".PadRight($labelWidth) + ": " + $sub.SubscriptionName) -ForegroundColor Green
            Write-Host ("  " + "Subscription ID".PadRight($labelWidth)   + ": " + $sub.SubscriptionId) -ForegroundColor Green
            Write-Host ("  " + "Subscription Status".PadRight($labelWidth) + ": " + $sub.SubscriptionState) -ForegroundColor Green
            Write-Host ""
        }
    }
    else {
        Write-Host "  [None]" -ForegroundColor DarkGray
    }

    # Output Not Owner list
    Write-Host ""
    Write-Host "─────────────────────────────────────────────────────────────────────"  -ForegroundColor Gray
    Write-Host " Subscriptions where user DOES NOT HAVE 'Owner' role:"                  -ForegroundColor Red
    Write-Host "─────────────────────────────────────────────────────────────────────"  -ForegroundColor Gray

    if ($notOwnerSubs.Count -gt 0) {
        foreach ($sub in $notOwnerSubs) {
            Write-Host ("  " + "Subscription Name".PadRight($labelWidth) + ": " + $sub.SubscriptionName) -ForegroundColor Red
            Write-Host ("  " + "Subscription ID".PadRight($labelWidth)   + ": " + $sub.SubscriptionId) -ForegroundColor Red
            Write-Host ("  " + "Subscription Status".PadRight($labelWidth) + ": " + $sub.SubscriptionState) -ForegroundColor Red
            Write-Host ""
        }
    }
    else {
        Write-Host "  [None]" -ForegroundColor DarkGray
    }

    # If missing Owner role, ask if proceed
    if ($notOwnerSubs.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARNING] User does not have Owner-role on all subscriptions." -ForegroundColor Yellow
        Write-Host "Do you wish to proceed onboarding the subscriptions where Owner-role is present? (Y/N)" -ForegroundColor Yellow

        $proceedConfirmation = Read-Host "Type Y to proceed or N to abort"

        if ($proceedConfirmation -notin @('Y', 'y')) {
            Write-Host ""
            Write-Host "═════════════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host "   ABORTED: User chose not to proceed." -ForegroundColor Red
            Write-Host "═════════════════════════════════════════════════════════════════════" -ForegroundColor Red
            exit 1
        }
    }

    # Final Status Summary
    Write-Host "[INFO] Checks complete. Proceeding to onboarding." -ForegroundColor Cyan
}
catch {
    Write-Host "[ERROR] An error occurred while checking role assignments: $_" -ForegroundColor Red
    exit 1
}

Start-Sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────
# PROCESSING ENABLED SUBSCRIPTIONS FOR AZURE LIGHTHOUSE ONBOARDING
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│         PROCESSING SUBSCRIPTIONS FOR LIGHTHOUSE ONBOARDING         │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# PARAMETERS — edit these to suit your environment
Write-Host "[INFO] Setting parameters for onboarding..."     -ForegroundColor Yellow

Start-Sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────
#      DEPLOYING AZURE LIGHTHOUSE TEMPLATE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                 DEPLOYING AZURE LIGHTHOUSE TEMPLATE                │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# 3b) Deploy (or re-deploy) the ARM template
Write-Host "[INFO] Deploying Azure Lighthouse template... Please wait..." -ForegroundColor Yellow
try {
    # Ensure $subId is defined from the current subscription context
    $subId = (Get-AzContext).Subscription.Id

    # Shorten the name so we never exceed 64 chars
    $shortSub = $subId.Substring(0, 8)
    $deployName = "LHO-$shortSub" # Unique name for the deployment
    $deployment = New-AzDeployment `
        -Name                  $deployName `
        -Location              $location `
        -TemplateFile          $templateFile `
        -TemplateParameterFile $paramsFile `
        -ErrorAction Stop

    Write-Host "[SUCCESS] Deployment succeeded ($deployName)." -ForegroundColor Green


# ─────────────────────────────────────────────────────────────────────────────
#      DEPLOYMENT DETAILS
# ─────────────────────────────────────────────────────────────────────────────

    Write-Host ""
    Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│                         DEPLOYMENT DETAILS                         │" -ForegroundColor Cyan
    Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""


    # Collect deployment details into a custom object
    $deploymentDetails = [PSCustomObject]@{
        ProvisioningState  = $deployment.ProvisioningState
        DeploymentName     = $deployment.DeploymentName
        Location           = $deployment.Location
        Timestamp          = $deployment.Timestamp
    }

    # Display the deployment details in a vertical format
    $esc     = [char]27
    $boldOn  = "${esc}[1m"
    $boldOff = "${esc}[22m"
    $pad     = 20  # Adjust label column width here

    $deploymentDetails.PSObject.Properties | ForEach-Object {
        $label = $_.Name
        $value = $_.Value

        # Write the label bold + green, padded to align the colons
        Write-Host -NoNewline (
            $boldOn + $label.PadRight($pad) + ":" + $boldOff
        ) -ForegroundColor Green

        # Then write the value, with a few spaces in front
        Write-Host "    $value"
    }

    # Add a separator line for clarity
    $sepLen = $pad + 5 + ($deploymentDetails.PSObject.Properties | Select-Object -First 1).Value.ToString().Length
    Write-Host ("─" * $sepLen) -ForegroundColor DarkGray
}
catch {
    Write-Host "[FAILED] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}


Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│               VERIFYING AZURE LIGHTHOUSE ONBOARDING                │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Verifying Azure Lighthouse onboarding for subscriptions where user has 'Owner' role..." -ForegroundColor Yellow

try {
    # Get all subscriptions
    $subscriptions = Get-AzSubscription -ErrorAction Stop

    # Filter subscriptions where the user has the 'Owner' role
    $ownerSubscriptions = @()
    foreach ($subscription in $subscriptions) {
        $subId = $subscription.Id
        $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$subId" -ErrorAction SilentlyContinue
        if ($roleAssignments.RoleDefinitionName -contains "Owner") {
            $ownerSubscriptions += $subscription
        }
    }

    if ($ownerSubscriptions.Count -eq 0) {
        Write-Host "[INFO] No subscriptions found where the user has the 'Owner' role. Exiting." -ForegroundColor Yellow
        exit 0
    }

    foreach ($subscription in $ownerSubscriptions) {
        $subId = $subscription.Id
        $subName = $subscription.Name

        Write-Host ""
        Write-Host "Processing subscription: $subName ($subId)" -ForegroundColor Cyan

        # Retrieve Lighthouse onboarding details for the current subscription
        $report = Get-AzManagedServicesDefinition `
            -Scope "/subscriptions/$subId" `
            -ErrorAction SilentlyContinue | ForEach-Object {

            $def              = $_
            $offerName        = $def.RegistrationDefinitionName
            $definitionId     = $def.Name
            $mspTenantId      = $def.ManagedByTenantId

            # Try to read the friendly tenant name; fall back to an ARM call if not present
            if ($def.PSObject.Properties.Match('ManagedByTenantName')) {
                $mspTenantName = $def.ManagedByTenantName
            }
            else {
                $fullDef = Get-AzResource `
                    -ResourceId $def.Id `
                    -ApiVersion 2022-10-01 `
                    -ExpandProperties
                $mspTenantName = $fullDef.Properties.managedByTenantName
            }

            foreach ($auth in $def.Authorization) {
                # Extract the GUID portion and resolve to friendly role name
                $guid     = ($auth.RoleDefinitionId -split '/')[-1]
                $roleObj  = Get-AzRoleDefinition -Id $guid -ErrorAction SilentlyContinue
                $roleName = if ($roleObj) { $roleObj.Name } else { '<unknown>' }

                # Determine PoC Group Status
                $pocGruppeStatus = if ($auth.PrincipalIdDisplayName -eq $pocGroupName -and $roleName -eq $pocGroupRole) {
                    "$pocGroupName has $pocGroupRole access"
                } else {
                    "$pocGroupName does not have $pocGroupRole access"
                }

                [PSCustomObject]@{
                    SubscriptionId       = $subId
                    SubscriptionName     = $subName
                    OfferName            = $offerName
                    DefinitionId         = $definitionId
                    ManagedByTenantId    = $mspTenantId
                    ManagedByTenantName  = $mspTenantName
                    PrincipalId          = $auth.PrincipalId
                    PrincipalName        = $auth.PrincipalIdDisplayName
                    RoleDefinitionId     = $auth.RoleDefinitionId
                    RoleName             = $roleName
                    PoCGruppeStatus      = $pocGruppeStatus
                }
            }
        }

        if ($report) {
            # ANSI escape sequences for bold
            $esc     = [char]27
            $boldOn  = "${esc}[1m"
            $boldOff = "${esc}[22m"
            $pad     = 20  # Adjust label column width here

            $report | ForEach-Object {
                # Pack up the fields you want to display in a consistent order
                $fields = [ordered]@{
                    ManagedByTenantName = $_.ManagedByTenantName
                    ManagedByTenantId   = $_.ManagedByTenantId
                    SubscriptionName    = $_.SubscriptionName
                    SubscriptionId      = $_.SubscriptionId
                    OfferName           = $_.OfferName
                    PrincipalName       = $_.PrincipalName
                    RoleName            = $_.RoleName
                    PoCGruppeStatus     = $_.PoCGruppeStatus
                }

                foreach ($label in $fields.Keys) {
                    $value = $fields[$label]

                    # Write the label bold + green, padded to align the colons
                    Write-Host -NoNewline (
                        $boldOn + $label.PadRight($pad) + ":" + $boldOff
                    ) -ForegroundColor Green

                    # Then write the value, with a few spaces in front
                    Write-Host "    $value"
                }

                # A separator line (length = label+padding+approx value width)
                $sepLen = $pad + 5 + ($fields.Values | Select-Object -First 1).Length
                Write-Host ("─" * $sepLen) -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "[INFO] No Lighthouse delegation found in this subscription." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "[ERROR] Failed to verify Azure Lighthouse onboarding: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────
# FINAL SUCCESS MESSAGE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│                   FINAL SUCCESS MESSAGE                    │" -ForegroundColor Green
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Green
Write-Host ""

Write-Host "[INFO] Azure Lighthouse onboarding complete!" -ForegroundColor Green
Write-Host "[INFO] Subscriptions can now be managed from Management Tenant through Azure Lighthouse in the Azure Portal" -ForegroundColor Green

Start-Sleep -Seconds 2
$null = $null