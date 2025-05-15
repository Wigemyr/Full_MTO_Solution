<#
Author          : Bakken, Anders Wigemyr
Date            : 15-05-2025
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
                  
Security        : This script requires Owner role on subscriptions and Global Administrator role in Entra ID
                  for full functionality. Following Azure RBAC least-privilege principle, it will attempt
                  to proceed with reduced functionality if Global Admin rights are not present.

Error handling  : Implements robust error handling with clear user feedback and diagnostic information
                  for troubleshooting failed deployments or permission issues.

Compliance      : Follows Azure Cloud Adoption Framework best practices for multi-tenant delegated
                  resource management with clear documentation of delegation relationships.

Verification    : Automatically verifies deployment success with detailed reporting of Lighthouse
                  registration status and assigned roles.

References      : - Azure Lighthouse documentation: https://docs.microsoft.com/en-us/azure/lighthouse/
                  - ARM template reference: https://docs.microsoft.com/en-us/azure/templates/
                  - Azure RBAC best practices: https://docs.microsoft.com/en-us/azure/role-based-access-control/best-practices
#>



# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────

# General settings
$location           = "norwayeast"                                  # Azure region for deployments - change if needed
$templateFile       = ".\templates\subscription.json"               # Path to ARM template
$paramsFile         = ".\templates\subscription.parameters.json"    # Path to ARM parameters file
$location           = "norwayeast"                                  # Azure region for deployments - change if needed

# Group settings
$GroupDisplayName   = "<Group displayname from 'management tenant'>"      # Display name of the PoC group
$GroupRoleName      = "<Role displayname ex.: Contributor/Reader...>"     # Role assigned to the PoC group



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Spinner helper (v2 — erases its own line, no “Done.”)
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
function Invoke-WithSpinner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,

        # minimum spin time in milliseconds (0 = no forced extra)
        [int]$MinimumMilliseconds = 0,

        # time between frames
        [int]$FrameDelayMs = 100
    )

    # start the work in a thread job
    $job     = Start-ThreadJob -ScriptBlock $ScriptBlock
    $frames  = @('|','/','-','\')
    $i       = 0
    $start   = Get-Date

    while ($true) {
        # draw a frame
        Write-Host -NoNewline ("`r{0} Loading..." -f $frames[$i % $frames.Count])
        $i++

        # compute elapsed
        $elapsedMs = ((Get-Date) - $start).TotalMilliseconds

        # if the work is done AND we've hit the minimum, break out **before** sleeping
        if ($job.State -ne 'Running' -and $elapsedMs -ge $MinimumMilliseconds) {
            break
        }

        # otherwise pause between frames
        Start-Sleep -Milliseconds $FrameDelayMs
    }

    # clear that line
    Write-Host "`r[2K" -NoNewline

    # return job output
    return Receive-Job -Job $job -Wait -AutoRemoveJob
}




# ─────────────────────────────────────────────────────────────────────────────
# PowerShell Version Check (Requires 7+)
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                      CHECK POWERSHELL VERSION                      │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Spinner while we validate the version (min. 1s)
Invoke-WithSpinner -ScriptBlock {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "`r[2K[ERROR] You are running PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Red
        Write-Host "[INFO] Please run this script using PowerShell 7 (e.g. 'pwsh.exe')." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "`r[2K[SUCCESS] PowerShell version $($PSVersionTable.PSVersion) detected. Continuing execution..." -ForegroundColor Green
    }
} -MinimumMilliseconds 1000



# ─────────────────────────────────────────────────────────────────────────────
# CHECK & INSTALL REQUIRED MODULES
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                   CHECK & INSTALL REQUIRED MODULES                 │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Define the required modules
$requiredModules = @("Az.Accounts", "Az.Resources", "Az.ManagedServices")

foreach ($module in $requiredModules) {
    # 1) Spinner while checking installation (min 1s)
    Invoke-WithSpinner -ScriptBlock {
        Get-Module -ListAvailable -Name $using:module
    } -MinimumMilliseconds 1000 | Out-Null
    # clear spinner
    Write-Host "`r[2K" -NoNewline

    $moduleInstalled = Get-Module -ListAvailable -Name $module
    if ($moduleInstalled) {
        Write-Host "[INFO]    Module '$module' is already installed." -ForegroundColor Green
    } else {
        Write-Host "[INFO]    Module '$module' not found. Installing..." -ForegroundColor Yellow

        # 2) Spinner while installing (min 1s)
        Invoke-WithSpinner -ScriptBlock {
            Install-Module $using:module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        } -MinimumMilliseconds 1000 | Out-Null
        # clear spinner
        Write-Host "`r[2K" -NoNewline

        # Verify installation
        $moduleInstalled = Get-Module -ListAvailable -Name $module
        if ($moduleInstalled) {
            Write-Host "[SUCCESS] Module '$module' installed successfully!" -ForegroundColor Green
        } else {
            Write-Host "[ERROR]   Module '$module' installation did not complete. Please install manually." -ForegroundColor Red
            exit 1
        }
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# SIGNING INTO AZURE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                        SIGNING INTO AZURE                          │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Signing into Azure..." -ForegroundColor Cyan
Invoke-WithSpinner -ScriptBlock {
    Connect-AzAccount -ErrorAction Stop | Out-Null
} -MinimumMilliseconds 1000 | Out-Null

Write-Host "[SUCCESS] Signed into Azure." -ForegroundColor Green




# ─────────────────────────────────────────────────────────────────────────────
# CHECK FOR GLOBAL ADMINISTRATOR IN ENTRA ID
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│           CHECKING GLOBAL ADMINISTRATOR ROLE IN ENTRA ID           │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

try {
    # Acquire token for Microsoft Graph (suppress warning)
    $token   = (Get-AzAccessToken -ResourceTypeName MSGraph -WarningAction SilentlyContinue).Token
    $headers = @{ Authorization = "Bearer $token" }
    $rolesUri = "https://graph.microsoft.com/v1.0/me/memberOf"

    Write-Host "[INFO] Verifying Global Administrator membership..." -ForegroundColor Cyan

    # Spinner while fetching directory roles (min 1s)
    $response = Invoke-WithSpinner -ScriptBlock {
        Invoke-RestMethod -Uri $using:rolesUri -Headers $using:headers -Method GET
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    # Check if Global Administrator is present
    $isGlobalAdmin = $response.value | Where-Object {
        $_.'@odata.type' -eq "#microsoft.graph.directoryRole" -and
        $_.displayName     -eq "Global Administrator"
    }

    if ($isGlobalAdmin) {
        Write-Host "[SUCCESS] User is a confirmed Global Administrator." -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] User is NOT a Global Administrator." -ForegroundColor Yellow
        Write-Host ""
        $proceed = Read-Host "Do you still wish to proceed without Global Administrator rights? (Y/N)"
        if ($proceed -notmatch '^[Yy]') {
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
    Invoke-WithSpinner -ScriptBlock {
        Connect-AzAccount -ErrorAction Stop | Out-Null
    } -MinimumMilliseconds 0 | Out-Null
    Write-Host "`r[2K" -NoNewline
}

# Get current signed-in user and tenant ID
$currentContext = Get-AzContext -ErrorAction Stop
$currentUserUpn = $currentContext.Account
$tenantId = $currentContext.Tenant.Id

# Resolve ObjectId from UPN or SPN
try {
    if ($currentUserUpn -match '@') {
        # User account
        $currentUserObjectId = (Get-AzADUser -UserPrincipalName $currentUserUpn -ErrorAction Stop).Id
    } else {
        # Likely a service principal
        $currentUserObjectId = (Get-AzADServicePrincipal -DisplayName $currentUserUpn -ErrorAction Stop).Id
    }
} catch {
    Write-Host "[ERROR] Could not retrieve ObjectId for $currentUserUpn. Ensure the account exists and you have permission to query Entra ID." -ForegroundColor Red
    exit 1
}

# Debugging outputs (commented out for future troubleshooting)
# Write-Host "[DEBUG] Current User UPN: $currentUserUpn" -ForegroundColor Yellow
# Write-Host "[DEBUG] Current User Object ID: $currentUserObjectId" -ForegroundColor Yellow
# Write-Host "[DEBUG] Current Tenant ID: $tenantId" -ForegroundColor Yellow

if (-not $currentUserUpn -or [string]::IsNullOrWhiteSpace($currentUserUpn)) {
    Write-Host "[ERROR] Could not determine signed-in user UPN. Please ensure you are signed in with a valid Azure account." -ForegroundColor Red
    Write-Host "[INFO] Try running 'Connect-AzAccount' manually to verify your account." -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Checking role assignments for user: $currentUserUpn" -ForegroundColor Yellow

try {
    $subscriptions = Invoke-WithSpinner -ScriptBlock {
        Get-AzSubscription -TenantId $tenantId -ErrorAction Stop
    } -MinimumMilliseconds 0
    Write-Host "`r[2K" -NoNewline

    if (-not $subscriptions -or $subscriptions.Count -eq 0) {
        Write-Host "[ERROR] No subscriptions found. Ensure your account has access." -ForegroundColor Red
        exit 1
    }

    $ownerSubs = @()
    $notOwnerSubs = @()
    $disabledSubs = @()

    foreach ($sub in $subscriptions) {
        if ($sub.State -ne "Enabled") {
            $disabledSubs += [PSCustomObject]@{
                SubscriptionName  = $sub.Name
                SubscriptionId    = $sub.Id
                SubscriptionState = $sub.State
            }
            continue
        }

        Write-Host "[INFO] Checking subscription: $($sub.Name)" -ForegroundColor Cyan

        try {
            $scope = "/subscriptions/$($sub.Id)"
            $roleAssignments = Invoke-WithSpinner -ScriptBlock {
                Get-AzRoleAssignment -ObjectId $using:currentUserObjectId -Scope $using:scope -ErrorAction SilentlyContinue
            } -MinimumMilliseconds 0
            Write-Host "`r[2K" -NoNewline

            $subInfo = [PSCustomObject]@{
                SubscriptionName  = $sub.Name
                SubscriptionId    = $sub.Id
                SubscriptionState = $sub.State
            }

            if ($roleAssignments -and ($roleAssignments.RoleDefinitionName -contains 'Owner')) {
                $ownerSubs += $subInfo
            } else {
                $notOwnerSubs += $subInfo
            }
        } catch {
            Write-Host "[ERROR] Failed to get role assignments for $($sub.Name): $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
    }

    $ownerSubs    = $ownerSubs    | Sort-Object SubscriptionName
    $notOwnerSubs = $notOwnerSubs | Sort-Object SubscriptionName
    $disabledSubs = $disabledSubs | Sort-Object SubscriptionName

    $labelWidth = 22

    Write-Host "`n─────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host " Subscriptions where user HAS 'Owner' role:" -ForegroundColor Green
    Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
    if ($ownerSubs.Count -gt 0) {
        foreach ($sub in $ownerSubs) {
            Write-Host ("  " + "Subscription Name".PadRight($labelWidth) + ": " + $sub.SubscriptionName) -ForegroundColor Green
            Write-Host ("  " + "Subscription ID".PadRight($labelWidth) + ": " + $sub.SubscriptionId) -ForegroundColor Green
            Write-Host ("  " + "Subscription Status".PadRight($labelWidth) + ": " + $sub.SubscriptionState) -ForegroundColor Green
            Write-Host ""
        }
    } else {
        Write-Host "  [None]" -ForegroundColor DarkGray
    }

    Write-Host "`n─────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host " Subscriptions where user DOES NOT HAVE 'Owner' role:" -ForegroundColor Red
    Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
    if ($notOwnerSubs.Count -gt 0) {
        foreach ($sub in $notOwnerSubs) {
            Write-Host ("  " + "Subscription Name".PadRight($labelWidth) + ": " + $sub.SubscriptionName) -ForegroundColor Red
            Write-Host ("  " + "Subscription ID".PadRight($labelWidth) + ": " + $sub.SubscriptionId) -ForegroundColor Red
            Write-Host ("  " + "Subscription Status".PadRight($labelWidth) + ": " + $sub.SubscriptionState) -ForegroundColor Red
            Write-Host ""
        }
    } else {
        Write-Host "  [None]" -ForegroundColor DarkGray
    }

    Write-Host "`n─────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host " Subscriptions which are DISABLED:" -ForegroundColor Yellow
    Write-Host "─────────────────────────────────────────────────────────────────────" -ForegroundColor Gray
    if ($disabledSubs.Count -gt 0) {
        foreach ($sub in $disabledSubs) {
            Write-Host ("  " + "Subscription Name".PadRight($labelWidth) + ": " + $sub.SubscriptionName) -ForegroundColor Yellow
            Write-Host ("  " + "Subscription ID".PadRight($labelWidth) + ": " + $sub.SubscriptionId) -ForegroundColor Yellow
            Write-Host ("  " + "Subscription Status".PadRight($labelWidth) + ": " + $sub.SubscriptionState) -ForegroundColor Yellow
            Write-Host ""
        }
    } else {
        Write-Host "  [None]" -ForegroundColor DarkGray
    }

    Write-Host ""
    $proceedToOnboarding = Read-Host "Do you wish to proceed to onboarding the subscriptions where Owner-role is present? (Y/N)"
    if ($proceedToOnboarding -notmatch '^[Yy]') {
        Write-Host "`n═════════════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "   ABORTED: User chose not to proceed." -ForegroundColor Red
        Write-Host "═════════════════════════════════════════════════════════════════════" -ForegroundColor Red
        exit 1
    }

    Write-Host "`n[INFO] Checks complete. Proceeding to onboarding." -ForegroundColor Cyan
}
catch {
    Write-Host "[ERROR] An error occurred while checking role assignments: $_" -ForegroundColor Red
    exit 1
}



# ─────────────────────────────────────────────────────────────────────────────
# PROCESSING ENABLED SUBSCRIPTIONS FOR AZURE LIGHTHOUSE ONBOARDING
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│         PROCESSING SUBSCRIPTIONS FOR LIGHTHOUSE ONBOARDING         │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Setting parameters for onboarding..." -ForegroundColor Yellow

# --- Fetch enabled subscriptions under spinner (no artificial delay) ---
$enabledSubscriptions = Invoke-WithSpinner -ScriptBlock {
    Get-AzSubscription | Where-Object State -eq 'Enabled'
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline


# ─────────────────────────────────────────────────────────────────────────────
#      DEPLOYING AZURE LIGHTHOUSE TEMPLATE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                 DEPLOYING AZURE LIGHTHOUSE TEMPLATE                │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# 3b) Prepare deployment parameters
$subId      = (Get-AzContext).Subscription.Id
$shortSub   = $subId.Substring(0, 8)
$deployName = "LHO-$shortSub"    # Unique name for the deployment

Write-Host "[INFO] Deploying Azure Lighthouse template..." -ForegroundColor Yellow

try {
    # Spinner while deploying (only as long as the deployment runs)
    $deployment = Invoke-WithSpinner -ScriptBlock {
        New-AzDeployment `
            -Name                  $using:deployName `
            -Location              $using:location `
            -TemplateFile          $using:templateFile `
            -TemplateParameterFile $using:paramsFile `
            -ErrorAction Stop
    } -MinimumMilliseconds 1000

    # Clear spinner line and show success immediately
    Write-Host "`r[2K" -NoNewline
    Write-Host "[SUCCESS] Deployment succeeded ($deployName)." -ForegroundColor Green
}
catch {
    Write-Host "`r[2K" -NoNewline
    Write-Host "[ERROR] Deployment failed: $_" -ForegroundColor Red
    exit 1
}



# ─────────────────────────────────────────────────────────────────────────────
#      DEPLOYMENT DETAILS
# ─────────────────────────────────────────────────────────────────────────────

try {
    Write-Host ""
    Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│                         DEPLOYMENT DETAILS                         │" -ForegroundColor Cyan
    Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
    Write-Host ""

    # Collect deployment details into a custom object
    $deploymentDetails = [PSCustomObject]@{
        ProvisioningState = $deployment.ProvisioningState
        DeploymentName    = $deployment.DeploymentName
        Location          = $deployment.Location
        Timestamp         = $deployment.Timestamp
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
    $firstValueLength = $deploymentDetails.PSObject.Properties |
        Select-Object -First 1 |
        ForEach-Object { $_.Value.ToString().Length }

    $sepLen = $pad + 5 + $firstValueLength
    Write-Host ("─" * $sepLen) -ForegroundColor DarkGray
}
catch {
    Write-Host "[FAILED] Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}


# ─────────────────────────────────────────────────────────────────────────────
#      VERIFYING DEPLOYMENT
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                        VERIFYING DEPLOYMENT                        │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Verifying Azure Lighthouse onboarding
Write-Host "[INFO] Verifying Azure Lighthouse onboarding..." -ForegroundColor Yellow

$report = Get-AzManagedServicesDefinition `
  -Scope "/subscriptions/$subId" `
  -ErrorAction SilentlyContinue | ForEach-Object {

    $def              = $_
    $offerName        = $def.RegistrationDefinitionName
    $definitionId     = $def.Name
    $mspTenantId      = $def.ManagedByTenantId

    # Fetch the subscription name
    $subName = (Get-AzSubscription -SubscriptionId $subId -ErrorAction SilentlyContinue).Name

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
    
        # Determine PoCGruppeStatus
        $pocGruppeStatus = if ($auth.PrincipalIdDisplayName -eq "$GroupDisplayName" -and $roleName -eq $GroupRoleName) {
            "$GroupDisplayName has $GroupRoleName access"
        } else {
            "$GroupDisplayName does not have $GroupRoleName access"
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



# ─────────────────────────────────────────────────────────────────────────────
# FINAL SUCCESS MESSAGE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│                   FINAL SUCCESS MESSAGE                    │" -ForegroundColor Green