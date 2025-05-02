<#
Author          : Bakken, Anders Wigemyr
Date            : 26-03-2025
Version         : 1.0
Description     : Automates the following steps:
                1. Validates PowerShell version (requires 7+)
                2. Loads required modules and connects to Microsoft Graph
                3. Invites users from a .csv and reads user data from the file and assigned specific string to employeeId
                4. Creates or reuses a PIM-enabled group for Security Administrator
                5. Creates an access package catalog and access package
                6. Adds the PIM group to the catalog as a resource
                7. Creates an auto-assignment policy using dynamic group membership rule using employeeId

Note            : Requires PowerShell 7+. Must be run with elevated permissions (Run as Administrator).
                  Script is unsigned – adjust execution policy accordingly (e.g., Bypass or Unrestricted).
                  Intended for internal administrative use only.

Script execution: accessPackageWithPIMGroup.ps1 -pathToCSV "C:\path\to\guests.csv"     
Attachements    : guestInvitation.csv (sample CSV file with guest details)

#>




# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# Path to CSV file with guest details
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# Requires user to provide the path to the CSV file containing guest details.
# The CSV file should contain the following columns: DisplayName and Email

# Example command to run the script: accessPackageWithPIMGroup.ps1 -pathToCSV "C:\path\to\guests.csv"

param (
    [string] $pathToCSV # Path to CSV file with guest details
)


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# VARIABLES SECTION
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

# Group-related variables
$groupName = "PIM - Security Admin Group" # Name for the PIM-enabled group
$groupDescription = "PIM-enabled group for Security Administrator role assignment" # Description for the group
$roleDisplayName = "Security Administrator" # Role to be assigned to the group

# Access Package-related variables
$catalogName = "Test Catalog" # Example name for the access package catalog
$accessPackageName = "Test Access Package" # Example name for the access package
$accessPackageDescription = "Test Access Package created via PowerShell" # Example description for the access package

# Auto-assignment policy variables
$autoPolicyName = "Test Auto-Assignment Policy" # Example name for the policy
$autoPolicyDescription = "Auto-assignment policy for employeeId" # Example description for the auto-assignment policy
$employeeIdFilter = '(user.employeeId -eq "n38fy345gf54")' # Example filter for employeeId with string "n38fy345gf54"
$policyDescription = "Auto-assignment policy for employeeId filter" # Example description for the policy

# Retry configuration
$retryCount = 5 # Number of retry attempts
$retryDelaySeconds = 5 # Delay between retries in seconds


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# PowerShell Version Check (Requires 7+)
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                  CHECK POWERSHELL VERSION                  │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


Write-Host "[INFO] This script requires PowerShell 7 or later." -ForegroundColor Yellow

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "[ERROR] You are running PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Red
    Write-Host "[INFO] Please run this script using PowerShell 7 (e.g. 'pwsh.exe')." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "[SUCCESS] PowerShell version $($PSVersionTable.PSVersion) detected. Continuing execution..." -ForegroundColor Green
}

start-sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# CHECK & INSTALL REQUIRED MODULES
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│              CHECK & INSTALL REQUIRED MODULES              │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# List of required modules
$requiredModules = @("Microsoft.Graph")

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

start-sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────
# CONNECT TO MICROSOFT GRAPH
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                 CONNECT TO MICROSOFT GRAPH                 │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


Write-Host "[INFO] Connecting to Microsoft Graph..." -ForegroundColor Cyan

try {
    Connect-MgGraph -Scopes "Application.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "EntitlementManagement.ReadWrite.All", "Group.ReadWrite.All" -ErrorAction Stop
    Write-Host "[SUCCESS] Connected to Microsoft Graph." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}

start-sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────
# CECK IF USER IS GLOBAL ADMINISTRATOR
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│            CHECK FOR CORRECT ROLE TO RUN SCRIPT            │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


# Required role
$requiredRole = "Global Administrator"

# Get current signed-in user
$currentUserUpn = (Get-MgContext).Account
$currentUser = Get-MgUser -UserId $currentUserUpn

# Get the enabled directory roles
$directoryRoles = Get-MgDirectoryRole -All | Where-Object { $_.DisplayName -eq $requiredRole }

if (-not $directoryRoles) {
    Write-Host "[ERROR] The role '$requiredRole' is not enabled in your tenant." -ForegroundColor Red
    exit 1
}

# Get members of the role
$roleId = $directoryRoles.Id
$roleMembers = Get-MgDirectoryRoleMember -DirectoryRoleId $roleId -All

# Check if the current user is a member
$isAuthorized = $roleMembers.Id -contains $currentUser.Id

if (-not $isAuthorized) {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "   You must be a Global Administrator to run this script." -ForegroundColor Red
    Write-Host "   Current user: $currentUserUpn" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
    exit 1
} else {
    Write-Host "[SUCCESS] User '$currentUserUpn' is a Global Administrator." -ForegroundColor Green
}

start-sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ADD PIM GROUP WITH ACTIVE ROLE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│               ADD PIM GROUP WITH ACTIVE ROLE               │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if group exists
$pimGroup = Get-MgGroup -Filter "displayName eq '$groupName'"
if ($pimGroup) {
    Write-Host "[INFO] PIM group '$groupName' already exists. Skipping creation." -ForegroundColor Yellow
} else {
    $pimGroup = New-MgGroup -DisplayName $groupName `
                            -Description $groupDescription `
                            -MailEnabled:$false `
                            -MailNickname ("pimSecAdmin" + (Get-Random -Maximum 9999)) `
                            -SecurityEnabled:$true `
                            -IsAssignableToRole:$true `
                            -Visibility "Private"
    Write-Host "[SUCCESS] Created PIM group: $($pimGroup.DisplayName)" -ForegroundColor Green
}

# Step 2: Find or enable the Security Administrator role
$role = Get-MgDirectoryRole | Where-Object { $_.DisplayName -eq $roleDisplayName }

# If not enabled, activate the directory role
if (-not $role) {
    $template = Get-MgDirectoryRoleTemplate | Where-Object { $_.DisplayName -eq $roleDisplayName }

    if ($template) {
        Write-Host "[INFO] Enabling role from template: $($template.DisplayName)" -ForegroundColor Yellow
        Enable-MgDirectoryRole -RoleTemplateId $template.Id | Out-Null
        Start-Sleep -Seconds 5
        $role = Get-MgDirectoryRole | Where-Object { $_.DisplayName -eq $roleDisplayName }
    } else {
        Write-Host "[ERROR] Could not find template for role '$roleDisplayName'" -ForegroundColor Red
        exit 1
    }
}


# Step 3: Check if group is already a member of the role
$existingMembers = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
$alreadyAssigned = $existingMembers.Id -contains $pimGroup.Id

if ($alreadyAssigned) {
    Write-Host "[INFO] Group is already assigned to the '$roleDisplayName' role. Skipping..." -ForegroundColor Yellow
} else {
    $refBody = @{
        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($pimGroup.Id)"
    }

    try {
        New-MgDirectoryRoleMemberByRef -DirectoryRoleId $role.Id -BodyParameter $refBody
        Write-Host "[SUCCESS] Assigned role '$roleDisplayName' to group: $($pimGroup.DisplayName)" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to assign group to role: $($_.Exception.Message)" -ForegroundColor Red
    }
}


Start-Sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# INVITE GUEST USER FROM MAIN TENANT
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│             INVITE GUEST USER FROM MAIN TENANT             │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "Starting invitation process ..." -ForegroundColor Cyan

$guestList = Import-Csv -Path $pathToCSV

# Prepare results array
$results = @()

foreach ($guest in $guestList) {
    $displayName = $guest.DisplayName
    $mainAdminEmail = $guest.Email
    $employeeId = $guest.EmployeeId

    # Check if guest already exists using the 'mail' property
    try {
        $existingGuest = Get-MgUser -Filter "mail eq '$mainAdminEmail'" -ConsistencyLevel eventual -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Failed to query mail '$mainAdminEmail': $_" -ForegroundColor Red
        continue
    }

    if ($existingGuest) {
        # Log that the user already exists and skip
        $results += [PSCustomObject]@{
            "User Principal Name" = $mainAdminEmail
            "Object ID"           = $existingGuest.Id
            "Status"              = "Guest already exists. Skipping invitation ..."
        }
        continue
    } else {
        # Invite the guest user
        try {
            $invitation = New-MgInvitation -InvitedUserDisplayName $displayName `
                                           -InvitedUserEmailAddress $mainAdminEmail `
                                           -InviteRedirectUrl "https://myapplications.microsoft.com" `
                                           -SendInvitationMessage:$true

            $guestId = $invitation.InvitedUser.Id

            # Log the invited user
            $results += [PSCustomObject]@{
                "User Principal Name" = $mainAdminEmail
                "Object ID"           = $guestId
                "Status"              = "Invitation sent, and user created."
            }
        } catch {
            $results += [PSCustomObject]@{
                "User Principal Name" = $mainAdminEmail
                "Object ID"           = "N/A"
                "Status"              = "Failed to invite: $($_.Exception.Message)"
            }
        }
    }
}

# Display results in a formatted table with wider column spacing
Write-Host ""
$results | Format-Table `
    @{Label = "User Principal Name"; Expression = { $_."User Principal Name".PadRight(50) } }, `
    @{Label = "Object ID"; Expression = { $_."Object ID".PadRight(40) } }, `
    @{Label = "Status"; Expression = { $_."Status".PadRight(60) } } -AutoSize

Start-Sleep -Seconds 5


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ADD STRING TO EMPLOYEE ID FILTER FOR ACCESS PACKAGE ASSIGNMENT
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│              ADD STRING TO EMPLOYEE ID FILTER              │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Hardcoded employeeId
$expectedEmployeeId = "n38fy345gf54"

# Import users from CSV
$users = Import-Csv -Path $pathToCSV

# Prepare results array
$results = @()

foreach ($user in $users) {
    $displayName = $user.DisplayName
    $email = $user.Email
    $employeeIdStatus = "Unknown"

    Write-Host "`nProcessing $email ..." -ForegroundColor Cyan

    $guest = $null
    # Retry logic to find the user
    for ($attempt = 1; $attempt -le $retryCount; $attempt++) {
        try {
            $guest = Get-MgUser -Filter "mail eq '$email'" -ConsistencyLevel eventual
            if ($guest) {
                break
            } else {
                Write-Host "[INFO] User not found yet (Attempt $attempt/$retryCount). Retrying in $retryDelaySeconds seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $retryDelaySeconds
            }
        } catch {
            Write-Host "[ERROR] Exception querying user: $_" -ForegroundColor Red
            break
        }
    }

    if (-not $guest) {
        Write-Host "[ERROR] Could not find user $email after $retryCount attempts." -ForegroundColor Red
        $results += [PSCustomObject]@{
            DisplayName      = $displayName
            Email            = $email
            EmployeeIdStatus = "User not found"
            OverallStatus    = "❌ Failed"
        }
        continue
    }

    $guestId = $guest.Id

    try {
        # Fetch current employeeId
        $currentEmployeeId = (Get-MgUser -UserId $guestId -Property "employeeId" | Select-Object -ExpandProperty employeeId)

        if ($currentEmployeeId -eq $expectedEmployeeId) {
            $employeeIdStatus = "Already correct"
            Write-Host "[INFO] Skipping update – employeeId already set to $expectedEmployeeId" -ForegroundColor Yellow
        } else {
            # Update employeeId
            Update-MgUser -UserId $guestId -BodyParameter @{ employeeId = $expectedEmployeeId }

            # Verify the update with a short delay
            Start-Sleep -Seconds 2
            $updatedEmployeeId = (Get-MgUser -UserId $guestId -Property "employeeId" | Select-Object -ExpandProperty employeeId)

            if ($updatedEmployeeId -eq $expectedEmployeeId) {
                $employeeIdStatus = "Updated to $expectedEmployeeId"
                Write-Host "[SUCCESS] Updated employeeId to $expectedEmployeeId for $email" -ForegroundColor Green
            } else {
                $employeeIdStatus = "Update failed"
                Write-Host "[WARNING] employeeId not updated for $email" -ForegroundColor Yellow
            }
        }

        # Add result to array
        $results += [PSCustomObject]@{
            DisplayName      = $displayName
            Email            = $email
            EmployeeIdStatus = $employeeIdStatus
            OverallStatus    = switch ($employeeIdStatus) {
                { $_ -match 'Updated' }        { '✅ Success' }
                { $_ -match 'Already correct'} { '⚠️ No action needed' }
                default                        { '❌ Failed' }
            }
        }
    }
    catch {
        Write-Host "[ERROR] Exception while processing $email - $_" -ForegroundColor Red
        $results += [PSCustomObject]@{
            DisplayName      = $displayName
            Email            = $email
            EmployeeIdStatus = "Error: $($_.Exception.Message)"
            OverallStatus    = "❌ Failed"
        }
    }
}

# Output summary table with wider spacing between columns
Write-Host ""
$results | Format-Table `
@{Label = "DisplayName"; Expression = { $_.DisplayName.PadRight(35) } },
@{Label = "Email"; Expression = { $_.Email.PadRight(55) } },
@{Label = "Employee ID Status"; Expression = { $_.EmployeeIdStatus.PadRight(30) } },
@{Label = "Overall Status"; Expression = { $_.OverallStatus } }


start-sleep -Seconds 2

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# IMPORTANT MESSAGE BEFORE PROCEEDING
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
Write-Host "│            IMPORTANT MESSAGE BEFORE PROCEEDING             │" -ForegroundColor Yellow
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
Write-Host ""

Write-Host ""
Write-Host "                           ⚠️   WARNING  ⚠️"                            -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════════════════════"  -ForegroundColor DarkYellow
Write-Host "       Access Package assignment may take up to 1 HOUR to apply       "  -ForegroundColor Yellow
Write-Host "             The role will not be granted immediately.               "   -ForegroundColor Gray
Write-Host "           This is expected behavior — do not troubleshoot.          "   -ForegroundColor Gray
Write-Host "══════════════════════════════════════════════════════════════════════"  -ForegroundColor DarkYellow
Write-Host ""


start-sleep -Seconds 7


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# CREATE OR FIND ACCESS PACKAGE CATALOG
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│           CREATE OR FIND ACCESS PACKAGE CATALOG            │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Checking for existing Access Package Catalog: '$catalogName'..." -ForegroundColor Cyan

$allCatalogs = Get-MgEntitlementManagementCatalog
$existingCatalog = $allCatalogs | Where-Object { $_.DisplayName -eq $catalogName }

if ($existingCatalog) {
    $catalogId = $existingCatalog.Id
    Write-Host "[SUCCESS] Found existing Access Package Catalog: '$catalogName' (ID: $catalogId)" -ForegroundColor Green
} else {
    Write-Host "[INFO] No catalog found. Creating a new catalog: '$catalogName'..." -ForegroundColor Yellow

    $catalogBody = @{
        DisplayName         = $catalogName
        Description         = "Catalog for access package automation"
        IsExternallyVisible = $false
    }

    # Create the catalog
    $newCatalog = New-MgEntitlementManagementCatalog -BodyParameter $catalogBody
    $catalogId = $newCatalog.Id
    Write-Host "[SUCCESS] Created catalog '$catalogName'. ID: $catalogId" -ForegroundColor Green
}

Start-Sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# CREATE OR FIND ACCESS PACKAGE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│               CREATE OR FIND ACCESS PACKAGE                │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


Write-Host "[INFO] Checking for existing Access Package: '$accessPackageName'..." -ForegroundColor Cyan

$existingPackage = Get-MgEntitlementManagementAccessPackage -Filter "displayName eq '$accessPackageName'" | Select-Object -First 1

if ($existingPackage) {
    $accessPackageId = $existingPackage.Id
    Write-Host "[SUCCESS] Found existing Access Package: '$accessPackageName' (ID: $accessPackageId)" -ForegroundColor Green
} else {
    Write-Host "[INFO] Creating new Access Package: '$accessPackageName'..." -ForegroundColor Yellow

    $params = @{
        displayName = $accessPackageName
        description = $accessPackageDescription
        isHidden = $false
        catalog = @{
            id = $catalogId
        }
    }

    # Create the Access Package
    $accessPackage = New-MgEntitlementManagementAccessPackage -BodyParameter $params
    $accessPackageId = $accessPackage.Id
    Write-Host "[SUCCESS] Created Access Package: '$accessPackageName' (ID: $accessPackageId)" -ForegroundColor Green
}

Start-Sleep -Seconds 2


# ──────────────────────────────────────────────────────────────────────────────
# ADD PIM GROUP WITH ROLE TO CATALOG
# ──────────────────────────────────────────────────────────────────────────────


Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│             ADD PIM GROUP WITH ROLE TO CATALOG             │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Variables (update with your actual values)
$CatalogId = $catalogId         # Example: "db4859bf-43c3-49fa-ab13-8036bd333ebe"
$GroupObjectId = $pimGroup.Id # Example: "b3b3b3b3-3b3b-3b3b-3b3b-3b3b3b3b3b3b"

# Check if group is already added to catalog
$existingResource = Get-MgEntitlementManagementCatalogResource `
    -AccessPackageCatalogId $CatalogId `
    -Filter "originId eq '$GroupObjectId' and originSystem eq 'AadGroup'"

if ($existingResource) {
    Write-Host "[INFO] Group is already in the catalog. Skipping." -ForegroundColor Yellow
} else {
    # Construct request body
    $GroupResourceAddParameters = @{
        requestType = "adminAdd"
        resource = @{
            originId     = $GroupObjectId
            originSystem = "AadGroup"
        }
        catalog = @{
            id = $CatalogId
        }
    }

    # Make the request
    try {
        Write-Host "[INFO] Adding group to catalog..." -ForegroundColor Cyan
        New-MgEntitlementManagementResourceRequest -BodyParameter $GroupResourceAddParameters | Out-Null
        Start-Sleep -Seconds 3

        # Validate addition
        $validation = Get-MgEntitlementManagementCatalogResource `
            -AccessPackageCatalogId $CatalogId `
            -Filter "originId eq '$GroupObjectId' and originSystem eq 'AadGroup'"

        if ($validation) {
            Write-Host "[SUCCESS] Group successfully added to the catalog." -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Could not verify if group was added. Please check manually." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[ERROR] Failed to add group to catalog: $($_.Exception.Message)" -ForegroundColor Red
    }
}

start-sleep -Seconds 2

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# LINK ACCESS PACKAGE CATALOG TO ACCESS PACKAGE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│       LINK ACCESS PACKAGE CATALOG TO ACCESS PACKAGE        │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


Write-Host "[INFO] Attempting to assign group '$($pimGroup.DisplayName)' to access package..." -ForegroundColor Yellow

# 1. Get the group resource from the catalog
$catalogResources = Get-MgEntitlementManagementCatalogResource -AccessPackageCatalogId $catalogId -ExpandProperty "scopes" -All
$groupResource = $catalogResources | Where-Object OriginId -eq $pimGroup.Id

if (-not $groupResource) {
    Write-Host "[ERROR] Group not found in catalog!" -ForegroundColor Red
    return
}

$groupResourceScope = $groupResource.Scopes[0]

# 2. Get the 'Member' role for the group
$filter = "(originSystem eq 'AadGroup' and resource/id eq '$($groupResource.Id)')"
$resourceRoles = Get-MgEntitlementManagementCatalogResourceRole -AccessPackageCatalogId $catalogId -Filter $filter -ExpandProperty "resource"
$memberRole = $resourceRoles | Where-Object DisplayName -eq "Member"

if (-not $memberRole) {
    Write-Host "[ERROR] 'Member' role not found for the group resource." -ForegroundColor Red
    return
}



#
# Add a check to ensure the group is not already assigned to the access package 
# Required beta graph
# Might Remove in the future
#


# 4. Construct body for assignment
$body = @{
    role = @{
        displayName   = "Member"
        description   = ""
        originSystem  = $memberRole.OriginSystem
        originId      = $memberRole.OriginId
        resource      = @{
            id           = $groupResource.Id
            originId     = $groupResource.OriginId
            originSystem = $groupResource.OriginSystem
        }
    }
    scope = @{
        id           = $groupResourceScope.Id
        originId     = $groupResourceScope.OriginId
        originSystem = $groupResourceScope.OriginSystem
    }
}

# 5. Assign group to access package
try {
    Write-Host "[INFO] Linking group to access package..." -ForegroundColor Yellow
    $null = New-MgEntitlementManagementAccessPackageResourceRoleScope -AccessPackageId $accessPackageId -BodyParameter $body
    Write-Host "[SUCCESS] Linked group to access package with 'Member' role." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to link group to access package: $_" -ForegroundColor Red
    Write-Host "[INFO] Request payload:" -ForegroundColor Yellow
    $body | ConvertTo-Json -Depth 10 | Write-Host
}



start-sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# CREATE AUTO-ASSIGNMENT POLICY (Fixed Rule Syntax)
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│     CREATE AUTO-ASSIGNMENT POLICY (Fixed Rule Syntax)      │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Validate accessPackageId
if (-not $accessPackageId -or -not [guid]::TryParse($accessPackageId, [ref]([guid]::Empty))) {
    throw "[ERROR] Invalid or missing accessPackageId: $accessPackageId"
}

Write-Host "[INFO] Checking for existing assignment policy named '$autoPolicyName'..." -ForegroundColor Cyan
$existingPolicy = Get-MgEntitlementManagementAssignmentPolicy -All
$policyId = ($existingPolicy | Where-Object { $_.DisplayName -eq $autoPolicyName }).Id

if ($policyId) {
    Write-Host "[SUCCESS] Found existing Assignment Policy '$autoPolicyName'. Skipping creation." -ForegroundColor Yellow
} else {
    Write-Host "[INFO] Creating new auto-assignment policy: '$autoPolicyName'" -ForegroundColor Cyan

    # 🛠 Build request body
    $autoPolicyParameters = @{
        DisplayName           = $autoPolicyName
        Description           = $autoPolicyDescription
        AllowedTargetScope    = "specificDirectoryUsers"
        SpecificAllowedTargets = @(
            @{
                "@odata.type"  = "#microsoft.graph.attributeRuleMembers"
                description    = $policyDescription
                membershipRule = $employeeIdFilter
            }
        )
        AutomaticRequestSettings = @{
            RequestAccessForAllowedTargets = $true
        }
        AccessPackage = @{
            Id = $accessPackageId
        }
    }

    # Send API request
    try {
        $newPolicy = New-MgEntitlementManagementAssignmentPolicy -BodyParameter $autoPolicyParameters
        Write-Host "[SUCCESS] Auto-assignment policy created successfully: $($newPolicy.Id)" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to create auto-assignment policy: $_" -ForegroundColor Red
        return
    }
    

    # Refresh $policyId after creation
    $policyId = $newPolicy.Id
}

# Final check
if (-not $policyId) {
    Write-Host "[ERROR] Policy ID not found after creation for '$autoPolicyName'." -ForegroundColor Red
} else {
    Write-Host "[INFO] Assignment policy ID: $policyId" -ForegroundColor Gray
}

# Optional: Pause before next steps
Start-Sleep -Seconds 2


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# FINAL SUCCESS MESSAGE (TABLE FORMAT)
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│                   FINAL SUCCESS MESSAGE                    │" -ForegroundColor Green
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Green
Write-Host ""


# Create an array of objects for structured output
$finalOutput = @(
    [PSCustomObject]@{ "Property" = "Access Package ID      "; "DisplayName    " = $accessPackageName ; "Value" = $accessPackageId }
    [PSCustomObject]@{ "Property" = "Policy ID             "; "DisplayName    " = $autoPolicyName ; "Value" = $policyId }
    [PSCustomObject]@{ "Property" = "Access Package Catalog      "; "DisplayName    " = $catalogName ; "Value" = $catalogId}
    [PSCustomObject]@{ "Property" = "Entra ID Role      "; "DisplayName    " = $Role.DisplayName ; "Value" = $Role.Id}
)

# Display as a formatted table with wider column spacing
$finalOutput | Format-Table

Write-Host "`n[SUCCESS] Access Package, Assignment Policy, and Access Package Catalog was created!" -ForegroundColor Green

Write-Host ""
Write-Host "                     ⚠️  IMPORTANT INFORMATION  ⚠️"                  -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════════════════════"  -ForegroundColor DarkYellow
Write-Host "     Please ensure that the guest invitations sent via email are      "  -ForegroundColor Yellow
Write-Host "     accepted by the recipients. This step is required to enable      "  -ForegroundColor Yellow
Write-Host "     access to the resources and functionality provided by the        "  -ForegroundColor Yellow
Write-Host "     access package.                                                  "  -ForegroundColor Yellow
Write-Host ""
Write-Host "     Once the invitation is accepted, users will be able to see       "  -ForegroundColor Gray
Write-Host "     and access the assigned resources in their My Apps portal:       "  -ForegroundColor Gray
Write-Host "     https://myapplications.microsoft.com                            "  -ForegroundColor Cyan
Write-Host ""
Write-Host "     This is expected behavior and does not require troubleshooting. "  -ForegroundColor Gray
Write-Host "══════════════════════════════════════════════════════════════════════"  -ForegroundColor DarkYellow
Write-Host ""

Write-Host "`n[SUCCESS] Script finished." -ForegroundColor Green

Start-Sleep -Seconds 1

Read-Host "Press any key to exit"