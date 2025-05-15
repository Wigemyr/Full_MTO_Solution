<#
Author          : Bakken, Anders Wigemyr
Date            : 05-05-2025
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
$groupName = "PIM - Security Admin Group" # Name for the PIM-enabled group being created
$groupDescription = "PIM-enabled group for Security Administrator role assignment" # Description for the group being created
$roleDisplayName = "Security Administrator" # Role to be assigned to the group that is being created

# Hardcoded employeeId
$expectedEmployeeId = "n38fy345gf54" # Example employeeId to be assigned to users

# Access Package-related variables
$catalogName = "Test Catalog" # Example name for the access package catalog being created
$accessPackageName = "Test Access Package" # Example name for the access package being created
$accessPackageDescription = "Test Access Package created via PowerShell" # Example description for the access package being created

# Auto-assignment policy variables
$autoPolicyName = "Test Auto-Assignment Policy" # Example name for the policy being created
$autoPolicyDescription = "Auto-assignment policy for employeeId" # Example description for the auto-assignment policy being created
$employeeIdFilter = '(user.employeeId -eq "n38fy345gf54")' # Example filter for employeeId with string "n38fy345gf54" being assigned to auto-assignment policy
$policyDescription = "Auto-assignment policy for employeeId filter" # Example description for the policy being created

# Retry configuration
$retryCount = 5 # Number of retry attempts for user-invite lookup
$retryDelaySeconds = 5 # Delay between retries in seconds


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ASYNCHRONOUS PROCESSING WITH VISUAL FEEDBACK
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
function Invoke-WithSpinner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,

        # Minimum display time in milliseconds (ensures spinner visibility for fast operations)
        [int]$MinimumMilliseconds = 0,

        # Animation speed - interval between animation frames in milliseconds
        [int]$FrameDelayMs = 100
    )

    # Execute operation in background thread to maintain UI responsiveness
    # This follows Azure best practice of keeping the main thread free for user interaction
    $job     = Start-ThreadJob -ScriptBlock $ScriptBlock
    $frames  = @('|','/','-','\')
    $i       = 0
    $start   = Get-Date

    while ($true) {
        # Display current animation frame (optimized for terminal readability)
        Write-Host -NoNewline ("`r{0} Loading..." -f $frames[$i % $frames.Count])
        $i++

        # Track elapsed time for minimum display duration enforcement
        $elapsedMs = ((Get-Date) - $start).TotalMilliseconds

        # Exit conditions: background job completed AND minimum display time met
        # This ensures users can see feedback even for fast Azure operations
        if ($job.State -ne 'Running' -and $elapsedMs -ge $MinimumMilliseconds) {
            break
        }

        # Control animation speed for consistent user experience
        Start-Sleep -Milliseconds $FrameDelayMs
    }

    # Clear the spinner line using ANSI escape sequence for clean output
    Write-Host "`r[2K" -NoNewline

    # Return operation results and clean up resources
    # Following Azure best practice of proper resource management
    return Receive-Job -Job $job -Wait -AutoRemoveJob
}


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT VALIDATION: POWERSHELL VERSION CHECK
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                  CHECK POWERSHELL VERSION                  │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] This script requires PowerShell 7 or later." -ForegroundColor Yellow

# Validate PowerShell version with visual feedback (minimum 1s display)
# PowerShell 7+ is required for Microsoft Graph module compatibility
Invoke-WithSpinner -ScriptBlock {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "[ERROR] You are running PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Red
        Write-Host "[INFO] Please run this script using PowerShell 7 (e.g. 'pwsh.exe')." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "[SUCCESS] PowerShell version $($PSVersionTable.PSVersion) detected. Continuing execution..." -ForegroundColor Green
    }
} -MinimumMilliseconds 1000


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# DEPENDENCY MANAGEMENT: MICROSOFT GRAPH MODULE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│              CHECK & INSTALL REQUIRED MODULES              │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Microsoft Graph module is essential for Entra ID and access package operations
$requiredModules = @("Microsoft.Graph")

foreach ($module in $requiredModules) {
    # Check for module availability with visual feedback
    # Following Azure best practice for graceful dependency validation
    $isInstalled = Invoke-WithSpinner -ScriptBlock {
        # Variable scope handling for background jobs
        if (Get-Module -ListAvailable -Name $using:module) { $true } else { $false }
    } -MinimumMilliseconds 1000

    if ($isInstalled) {
        Write-Host "[INFO] Module '$module' is already installed." -ForegroundColor Green
        continue
    }

    # Interactive module installation with user consent
    # Azure best practice: Always prompt before modifying system state
    Write-Host "[WARNING] Module '$module' not found." -ForegroundColor Yellow
    $ans = Read-Host "    Install '$module' now? (Y/N)"
    if ($ans -notmatch '^[Yy]') {
        Write-Host "[ERROR] Module '$module' is required. Exiting." -ForegroundColor Red
        exit 1
    }

    # Install module with visual feedback
    # Using CurrentUser scope for least-privilege installation
    Invoke-WithSpinner -ScriptBlock {
        Install-Module $using:module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } -MinimumMilliseconds 1000 | Out-Null

    Write-Host "[SUCCESS] Module '$module' installed successfully!" -ForegroundColor Green
}


# ─────────────────────────────────────────────────────────────────────────────
# AUTHENTICATION: MICROSOFT GRAPH API CONNECTION
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                 CONNECT TO MICROSOFT GRAPH                 │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Connecting to Microsoft Graph..." -ForegroundColor Cyan

try {
    # Connect to Microsoft Graph with required permissions for access package management
    # Following Azure least-privilege principle by requesting only needed scopes
    Invoke-WithSpinner -ScriptBlock {
        Connect-MgGraph `
            -Scopes "Application.ReadWrite.All", "RoleManagement.ReadWrite.Directory", `
                    "EntitlementManagement.ReadWrite.All", "Group.ReadWrite.All", "User.ReadWrite.All" `
            -ErrorAction Stop
    } -MinimumMilliseconds 1000 | Out-Null

    Write-Host "[SUCCESS] Connected to Microsoft Graph." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit 1
}



# ─────────────────────────────────────────────────────────────────────────────
# PERMISSION VALIDATION: GLOBAL ADMINISTRATOR ROLE CHECK
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│            CHECK FOR CORRECT ROLE TO RUN SCRIPT            │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Global Administrator role is required for access package and PIM operations
$requiredRole = "Global Administrator"
Write-Host "[INFO] Checking if user is '$requiredRole'..." -ForegroundColor Cyan

# Retrieve current user's role membership with visual feedback
# Following Azure best practice for thorough permission validation
$authInfo = Invoke-WithSpinner -ScriptBlock {
    $upn     = (Get-MgContext).Account
    $user    = Get-MgUser -UserId $upn
    $role    = Get-MgDirectoryRole -All | Where-Object { $_.DisplayName -eq $using:requiredRole }
    $members = if ($role) { Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All } else { @() }

    # Return structured information for role validation
    [pscustomobject]@{
        UPN     = $upn
        UserId  = $user.Id
        Role    = $role
        Members = $members
    }
} -MinimumMilliseconds 1000

# Clear spinner line for clean output
Write-Host "`r[2K" -NoNewline

# Verify role existence in tenant
if (-not $authInfo.Role) {
    Write-Host "[ERROR] The role '$requiredRole' is not enabled in your tenant." -ForegroundColor Red
    exit 1
}

# Verify current user has the required role
# Following Azure security principle of validating permissions before execution
$hasRole = $authInfo.Members.Id -contains $authInfo.UserId
if (-not $hasRole) {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "   You must be a Global Administrator to run this script." -ForegroundColor Red
    Write-Host "   Current user: $($authInfo.UPN)" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Red
    exit 1
} else {
    Write-Host "[SUCCESS] User '$($authInfo.UPN)' is a Global Administrator." -ForegroundColor Green
}


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# PRIVILEGED ACCESS MANAGEMENT: CREATE PIM GROUP WITH DIRECTORY ROLE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│               ADD PIM GROUP WITH ACTIVE ROLE               │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Required configuration variables for this section:
#   $groupName - Name for the role-assignable group (set in VARIABLES section)
#   $groupDescription - Group description text (set in VARIABLES section)
#   $roleDisplayName - Azure AD directory role to assign (set in VARIABLES section)

# --- Step 1: Check if the PIM-enabled group already exists in the tenant ---
# Using -All parameter for complete tenant search following Azure best practice for directory queries
$pimGroup = Invoke-WithSpinner -ScriptBlock {
    Get-MgGroup -All | Where-Object DisplayName -eq $using:groupName
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($pimGroup) {
    Write-Host "[INFO]    PIM group '$groupName' already exists. Skipping creation." -ForegroundColor Yellow
}
else {
    # --- Step 1b: Create the role-assignable group with PIM eligibility ---
    # Key security properties:
    # - IsAssignableToRole:$true - Enables PIM functionality for the group
    # - SecurityEnabled:$true - Required for role assignment
    # - MailEnabled:$false - Security group, not mail-enabled security group
    # - Visibility:Private - Restricted visibility following least privilege
    $pimGroup = Invoke-WithSpinner -ScriptBlock {
        New-MgGroup `
            -DisplayName        $using:groupName `
            -Description        $using:groupDescription `
            -MailEnabled:$false `
            -MailNickname       ("pimSecAdmin" + (Get-Random -Maximum 9999)) `
            -SecurityEnabled:$true `
            -IsAssignableToRole:$true `
            -Visibility         "Private"
    } -MinimumMilliseconds 1000

    Write-Host "`r[2K" -NoNewline
    Write-Host "[SUCCESS] Created PIM group: $($pimGroup.DisplayName)" -ForegroundColor Green
}

# Store ID for thread-safe usage in background jobs
$pimGroupId = $pimGroup.Id

# --- Step 2: Activate the required directory role if not already active ---
# Azure AD roles must be activated before assignment using the role template
# This is a key Entra ID security pattern for enabling predefined roles
$role = Invoke-WithSpinner -ScriptBlock {
    # First attempt direct retrieval of active role
    $r = Get-MgDirectoryRole | Where-Object DisplayName -eq $using:roleDisplayName
    if (-not $r) {
        # If not found, find the role template and activate it
        $t = Get-MgDirectoryRoleTemplate | Where-Object DisplayName -eq $using:roleDisplayName
        if ($t) { Enable-MgDirectoryRole -RoleTemplateId $t.Id | Out-Null }
        
        # Wait for role activation to propagate (Azure AD replication delay)
        # This follows Azure best practice for role activation operations
        Start-Sleep -Seconds 5
        
        # Retry role retrieval after activation
        $r = Get-MgDirectoryRole | Where-Object DisplayName -eq $using:roleDisplayName
    }
    return $r
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if (-not $role) {
    Write-Host "[ERROR] Could not find or enable role '$roleDisplayName'." -ForegroundColor Red
    exit 1
}

# Store ID for thread-safe usage in background jobs
$roleId = $role.Id

# --- Step 3: Check if group is already assigned to the role ---
# Verify existing membership before attempting assignment to prevent errors
# Following Azure best practice of idempotent operations
$alreadyAssigned = Invoke-WithSpinner -ScriptBlock {
    (Get-MgDirectoryRoleMember -DirectoryRoleId $using:roleId -All).Id -contains $using:pimGroupId
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($alreadyAssigned) {
    Write-Host "[INFO]    Group '$groupName' is already assigned to '$roleDisplayName'. Skipping..." -ForegroundColor Yellow
}
else {
    # --- Step 3b: Perform the role assignment using Graph API ---
    # Using reference-based assignment with proper OData reference format
    # This is the Microsoft recommended method for directory role assignments
    Invoke-WithSpinner -ScriptBlock {
        $body = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$using:pimGroupId" }
        New-MgDirectoryRoleMemberByRef -DirectoryRoleId $using:roleId -BodyParameter $body
    } -MinimumMilliseconds 1000 | Out-Null

    Write-Host "`r[2K" -NoNewline
    Write-Host "[SUCCESS] Assigned role '$roleDisplayName' to group: $groupName" -ForegroundColor Green
}





# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# EXTERNAL IDENTITY MANAGEMENT: GUEST USER INVITATION
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│             INVITE GUEST USER FROM MAIN TENANT             │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Starting invitation process..." -ForegroundColor Cyan

# Load user data from CSV file provided as parameter
# Standard CSV import is fast enough that a spinner isn't necessary
$guestList = Import-Csv -Path $pathToCSV

# Create tracking collection for batch operations and reporting
# Azure best practice: Log and track identity operations for audit purposes
$results = @()

foreach ($guest in $guestList) {
    $displayName    = $guest.DisplayName
    $mainAdminEmail = $guest.Email
    $employeeId     = $guest.EmployeeId

    # --- Check if guest already exists to avoid duplicate invitations ---
    # Using ConsistencyLevel eventual and filter for optimal performance
    # Following Azure best practice for directory queries
    $existingGuest = Invoke-WithSpinner -ScriptBlock {
        Get-MgUser -Filter "mail eq '$using:mainAdminEmail'" -ConsistencyLevel eventual -ErrorAction Stop
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    if ($existingGuest) {
        # Track existing users to avoid re-invitation
        # Following Azure best practice for idempotent operations
        $results += [PSCustomObject]@{
            "User Principal Name" = $mainAdminEmail
            "Object ID"           = $existingGuest.Id
            "Status"              = "Guest already exists. Skipping invitation."
        }
        continue
    }

    # --- Create and send invitation to external user ---
    # Using Microsoft Graph invitations API for secure B2B collaboration
    # Following Azure security best practice for external identity management
    $invitation = Invoke-WithSpinner -ScriptBlock {
        New-MgInvitation `
            -InvitedUserDisplayName    $using:displayName `
            -InvitedUserEmailAddress   $using:mainAdminEmail `
            -InviteRedirectUrl         "https://myapplications.microsoft.com" `
            -SendInvitationMessage:$true
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    if ($invitation) {
        # Record successful invitation with Azure B2B user ID
        $results += [PSCustomObject]@{
            "User Principal Name" = $mainAdminEmail
            "Object ID"           = $invitation.InvitedUser.Id
            "Status"              = "Invitation sent, and user created."
        }
    } else {
        # Track failed invitations for troubleshooting
        $results += [PSCustomObject]@{
            "User Principal Name" = $mainAdminEmail
            "Object ID"           = "N/A"
            "Status"              = "Failed to invite."
        }
    }
}

# Display formatted results table for better readability
# Following Azure best practice for administrative reporting
Write-Host ""
$results | Format-Table `
    @{Label="User Principal Name"; Expression={$_. "User Principal Name".PadRight(50)} }, `
    @{Label="Object ID";           Expression={$_. "Object ID".PadRight(40)} }, `
    @{Label="Status";              Expression={$_. "Status".PadRight(60)} } -AutoSize

# Brief delay to ensure output is readable before proceeding
Start-Sleep -Seconds 2



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# USER ATTRIBUTE MANAGEMENT: SET EMPLOYEE ID FOR ACCESS POLICY TARGETING
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│              ADD STRING TO EMPLOYEE ID FILTER              │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Import users from CSV file - using the source imported earlier
# Results array to track operation status for each user
$users   = Import-Csv -Path $pathToCSV
$results = @()

foreach ($user in $users) {
    $displayName = $user.DisplayName
    $email       = $user.Email

    Write-Host "`nProcessing $email ..." -ForegroundColor Cyan

    # --- Step A: Find the user with retry logic ---
    # Using retry pattern to accommodate B2B invitation propagation delay
    # Following Azure best practice for handling eventual consistency
    $guest = $null
    for ($attempt = 1; $attempt -le $retryCount; $attempt++) {
        try {
            $guest = Invoke-WithSpinner -ScriptBlock {
                Get-MgUser -Filter "mail eq '$using:email'" -ConsistencyLevel eventual -ErrorAction Stop
            } -MinimumMilliseconds 1000
            Write-Host "`r[2K" -NoNewline

            if ($guest) { break }
            Write-Host "[INFO] User not found yet (Attempt $attempt/$retryCount)." -ForegroundColor Yellow
            Start-Sleep -Seconds $retryDelaySeconds
        } catch {
            Write-Host "`r[2K" -NoNewline
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
        # --- Step B: Fetch current employeeId attribute ---
        # Retrieving only the needed property for efficiency
        # This follows Azure best practice for targeted property retrieval
        $currentEmployeeId = Invoke-WithSpinner -ScriptBlock {
            Get-MgUser -UserId $using:guestId -Property "employeeId" |
                Select-Object -ExpandProperty employeeId
        } -MinimumMilliseconds 1000
        Write-Host "`r[2K" -NoNewline

        if ($currentEmployeeId -eq $expectedEmployeeId) {
            $status = "Already correct"
            Write-Host "[INFO] Skipping update – employeeId already set to $expectedEmployeeId" -ForegroundColor Yellow
        } else {
            # --- Step C: Update employeeId attribute ---
            # Using partial update pattern to modify only the required attribute
            # Following Azure best practice for minimal-impact directory updates
            Invoke-WithSpinner -ScriptBlock {
                Update-MgUser -UserId $using:guestId -BodyParameter @{ employeeId = $using:expectedEmployeeId }
            } -MinimumMilliseconds 1000 | Out-Null
            Write-Host "`r[2K" -NoNewline

            # --- Step D: Verify update was successful ---
            # Implementing verification pattern for critical attribute changes
            # This follows Azure security best practice for update confirmation
            $updatedEmployeeId = Invoke-WithSpinner -ScriptBlock {
                Get-MgUser -UserId $using:guestId -Property "employeeId" |
                    Select-Object -ExpandProperty employeeId
            } -MinimumMilliseconds 1000
            Write-Host "`r[2K" -NoNewline

            if ($updatedEmployeeId -eq $expectedEmployeeId) {
                $status = "Updated to $expectedEmployeeId"
                Write-Host "[SUCCESS] Updated employeeId to $expectedEmployeeId for $email" -ForegroundColor Green
            } else {
                $status = "Update failed"
                Write-Host "[WARNING] employeeId not updated for $email" -ForegroundColor Yellow
            }
        }

        # Log result with detailed status tracking
        # Using structured objects for consistent reporting
        $results += [PSCustomObject]@{
            DisplayName      = $displayName
            Email            = $email
            EmployeeIdStatus = $status
            OverallStatus    = switch ($status) {
                { $_ -match 'Updated' }         { '✅ Success' }
                { $_ -match 'Already correct'}  { '⚠️ No action needed' }
                Default                         { '❌ Failed' }
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

# Display formatted summary table for better readability
# Following Azure best practice for administrative reporting
Write-Host ""
$results | Format-Table `
    @{Label="DisplayName";           Expression={ $_.DisplayName.PadRight(35) }}, `
    @{Label="Email";                 Expression={ $_.Email.PadRight(55) }}, `
    @{Label="Employee ID Status";    Expression={ $_.EmployeeIdStatus.PadRight(30) }}, `
    @{Label="Overall Status";        Expression={ $_.OverallStatus } }



# ─────────────────────────────────────────────────────────────────────────────
# ACCESS PACKAGE DEPLOYMENT NOTICE
# ─────────────────────────────────────────────────────────────────────────────

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

# User confirmation before proceeding with Access Package creation
# Following Azure best practice for interactive automation with checkpoints
Read-Host -Prompt "Press Enter to proceed"



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# CREATE OR FIND ACCESS PACKAGE CATALOG
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│           CREATE OR FIND ACCESS PACKAGE CATALOG            │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Checking for existing Access Package Catalog: '$catalogName'..." -ForegroundColor Cyan

# --- Spinner while fetching catalogs ---
$allCatalogs = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalog -All
} -MinimumMilliseconds 1000
# clear spinner line
Write-Host "`r[2K" -NoNewline

$existingCatalog = $allCatalogs | Where-Object DisplayName -eq $catalogName

if ($existingCatalog) {
    $catalogId = $existingCatalog.Id
    Write-Host "[SUCCESS] Found existing Access Package Catalog: '$catalogName' (ID: $catalogId)" -ForegroundColor Green
}
else {
    Write-Host "[INFO] No catalog found. Creating a new catalog: '$catalogName'..." -ForegroundColor Yellow

    $catalogBody = @{
        DisplayName         = $catalogName
        Description         = "Catalog for access package automation"
        IsExternallyVisible = $false
    }

    # --- Spinner while creating catalog ---
    $newCatalog = Invoke-WithSpinner -ScriptBlock {
        New-MgEntitlementManagementCatalog -BodyParameter $using:catalogBody
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    $catalogId = $newCatalog.Id
    Write-Host "[SUCCESS] Created catalog '$catalogName'. ID: $catalogId" -ForegroundColor Green
}



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ENTITLEMENT MANAGEMENT: CREATE OR FIND ACCESS PACKAGE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│               CREATE OR FIND ACCESS PACKAGE                │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Checking for existing Access Package: '$accessPackageName'..." -ForegroundColor Cyan

# --- Fetch all packages with retrieval optimization pattern ---
# Using single bulk fetch and client-side filtering for better performance
# This follows Azure best practice for minimizing API calls
$allPackages = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementAccessPackage -All
} -MinimumMilliseconds 1000
# clear spinner line
Write-Host "`r[2K" -NoNewline

# Apply client-side filter with exact name matching
# Select-Object -First 1 ensures consistent behavior if multiple matches exist
$existingPackage = $allPackages |
    Where-Object DisplayName -eq $accessPackageName |
    Select-Object -First 1

if ($existingPackage) {
    # Reuse existing package following idempotent operation pattern
    # This enables safe script re-execution without duplication
    $accessPackageId = $existingPackage.Id
    Write-Host "[SUCCESS] Found existing Access Package: '$accessPackageName' (ID: $accessPackageId)" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Creating new Access Package: '$accessPackageName'..." -ForegroundColor Yellow

    # Configure package with catalog reference
    # isHidden:$false makes package visible in MyAccess portal for better discoverability
    $params = @{
        displayName = $accessPackageName
        description = $accessPackageDescription
        isHidden    = $false
        catalog     = @{ id = $catalogId }
    }

    # --- Create package with visual progress feedback ---
    # Providing meaningful user experience for potentially slow operations
    $accessPackage = Invoke-WithSpinner -ScriptBlock {
        New-MgEntitlementManagementAccessPackage -BodyParameter $using:params
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    $accessPackageId = $accessPackage.Id
    Write-Host "[SUCCESS] Created Access Package: '$accessPackageName' (ID: $accessPackageId)" -ForegroundColor Green
}


# ──────────────────────────────────────────────────────────────────────────────
# RESOURCE MANAGEMENT: ADD PIM GROUP TO ACCESS CATALOG
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│             ADD PIM GROUP WITH ROLE TO CATALOG             │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


$GroupObjectId = $pimGroup.Id

# --- Step 1: Verify if group already exists in catalog ---
# Using precise OData filter for targeted resource lookup
# This follows Azure best practice for efficient resource querying
$exists = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResource `
      -AccessPackageCatalogId $using:catalogId `
      -Filter "originId eq '$using:GroupObjectId' and originSystem eq 'AadGroup'"
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($exists) {
    Write-Host "[INFO] Already in catalog. Skipping." -ForegroundColor Yellow
    return
}

# --- Step 2: Add group to catalog using resource request API ---
# Using adminAdd request type for immediate approval without review
# This provides more direct control than standard user-initiated requests
Write-Host "[INFO] Adding group to catalog…" -ForegroundColor Cyan
Invoke-WithSpinner -ScriptBlock {
    New-MgEntitlementManagementResourceRequest `
      -RequestType 'adminAdd' `
      -Resource @{ originId     = $using:GroupObjectId
                   originSystem = 'AadGroup' } `
      -Catalog  @{ id = $using:catalogId }
} -MinimumMilliseconds 1000 | Out-Null
Write-Host "`r[2K" -NoNewline

# --- Step 3: Verify resource addition with explicit validation ---
# Implementing verification pattern for critical operations
# This follows Azure security best practice for change confirmation
$valid = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResource `
      -AccessPackageCatalogId $using:catalogId `
      -Filter "originId eq '$using:GroupObjectId' and originSystem eq 'AadGroup'"
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($valid) {
    Write-Host "[SUCCESS] Group successfully added to catalog." -ForegroundColor Green
} else {
    # Detailed warning for manual verification
    # This helps troubleshoot asynchronous processing issues in the Entra ID backend
    Write-Host "[WARNING] Could not verify – please check manually." -ForegroundColor Yellow
}



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# RESOURCE ROLE ASSIGNMENT: LINK GROUP TO ACCESS PACKAGE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│       LINK ACCESS PACKAGE CATALOG TO ACCESS PACKAGE        │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Attempting to assign group '$($pimGroup.DisplayName)' to access package..." -ForegroundColor Yellow

# --- Step 1: Retrieve group resource details from catalog ---
# Using ExpandProperty to minimize API calls and improve performance
# This follows Azure best practice for efficient data retrieval
$catalogResources = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResource `
      -AccessPackageCatalogId $using:catalogId `
      -ExpandProperty "scopes" -All
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

# Find the specific resource by matching the Origin ID
# Origin ID is the unique external identifier for cross-referencing
$groupResource = $catalogResources | Where-Object OriginId -eq $pimGroup.Id
if (-not $groupResource) {
    Write-Host "[ERROR] Group not found in catalog!" -ForegroundColor Red
    return
}

# Extract scope information from the expanded properties
# Scope defines the permission boundary for the resource
$groupResourceScope = $groupResource.Scopes[0]

# --- Step 2: Retrieve available roles for the group ---
# Construct precise OData filter for targeted role lookup
# This follows Azure best practice for efficient Graph API querying
$filter = "(originSystem eq 'AadGroup' and resource/id eq '$($groupResource.Id)')"
$resourceRoles = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResourceRole `
      -AccessPackageCatalogId $using:catalogId `
      -Filter $using:filter `
      -ExpandProperty "resource"
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

# Target the specific "Member" role required for group membership
# Member role is the standard role for group access in Entra ID
$memberRole = $resourceRoles | Where-Object DisplayName -eq "Member"
if (-not $memberRole) {
    Write-Host "[ERROR] 'Member' role not found for the group resource." -ForegroundColor Red
    return
}

# --- Step 3: Prepare assignment payload with complete reference structure ---
# Following Microsoft Graph API schema requirements for role assignment
# This ensures all required relationship references are properly established
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

# --- Step 4: Execute role assignment with error handling ---
# Implementing try-catch pattern for robust error management
# This follows Azure best practice for reliable automation
try {
    Write-Host "[INFO] Linking group to access package..." -ForegroundColor Yellow
    Invoke-WithSpinner -ScriptBlock {
        New-MgEntitlementManagementAccessPackageResourceRoleScope `
          -AccessPackageId $using:accessPackageId `
          -BodyParameter $using:body
    } -MinimumMilliseconds 1000 | Out-Null
    Write-Host "`r[2K" -NoNewline
    Write-Host "[SUCCESS] Linked group to access package with 'Member' role." -ForegroundColor Green
}
catch {
    Write-Host "`r[2K" -NoNewline
    Write-Host "[ERROR] Failed to link group to access package: $_" -ForegroundColor Red
    # Display diagnostic payload for troubleshooting
    # This helps administrators resolve API format issues
    Write-Host "[INFO] Request payload:" -ForegroundColor Yellow
    $body | ConvertTo-Json -Depth 10 | Write-Host
}



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ACCESS POLICY MANAGEMENT: CREATE ATTRIBUTE-BASED AUTO-ASSIGNMENT
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│     CREATE AUTO-ASSIGNMENT POLICY (Fixed Rule Syntax)      │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Validate required parameters to prevent invalid policy creation
# Following Azure best practice for parameter validation before API calls
if (-not $accessPackageId -or -not [guid]::TryParse($accessPackageId, [ref]([guid]::Empty))) {
    throw "[ERROR] Invalid or missing accessPackageId: $accessPackageId"
}

Write-Host "[INFO] Checking for existing assignment policies..." -ForegroundColor Cyan

# --- Step 1: Retrieve all policies for client-side filtering ---
# Using bulk retrieval pattern for more efficient processing
$allPolicies = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementAssignmentPolicy -All
} -MinimumMilliseconds 1000
# clear spinner line
Write-Host "`r[2K" -NoNewline

# --- Step 2: Check for existing policy by display name ---
# Implementing idempotent pattern to prevent duplicate policies
$existingPolicy = $allPolicies | Where-Object DisplayName -eq $autoPolicyName

if ($existingPolicy) {
    $policyId = $existingPolicy.Id
    Write-Host "[SUCCESS] Found existing Assignment Policy '$autoPolicyName'. Skipping creation." -ForegroundColor Yellow
}
else {
    Write-Host "[INFO] Creating new auto-assignment policy: '$autoPolicyName'..." -ForegroundColor Cyan

    # --- Step 3: Configure policy with attribute-based targeting ---
    # Construct policy with dynamic membership rule using employeeId
    # Following Azure best practice for attribute-based access control
    $autoPolicyParameters = @{
        displayName            = $autoPolicyName
        description            = $autoPolicyDescription
        allowedTargetScope     = "specificDirectoryUsers" # Target specific users via rules
        specificAllowedTargets = @(
            @{
                # Use attribute rule to dynamically assign based on employeeId
                "@odata.type"   = "#microsoft.graph.attributeRuleMembers"
                description     = $policyDescription
                membershipRule  = $employeeIdFilter # KQL-like syntax for targeting
            }
        )
        automaticRequestSettings = @{
            # Enable auto-provisioning without user request
            requestAccessForAllowedTargets = $true
        }
        accessPackage = @{ id = $accessPackageId }
    }

    # --- Step 4: Create policy with visual progress feedback ---
    $newPolicy = Invoke-WithSpinner -ScriptBlock {
        New-MgEntitlementManagementAssignmentPolicy -BodyParameter $using:autoPolicyParameters
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    # Verify successful creation and provide clear success/failure indication
    if ($newPolicy) {
        $policyId = $newPolicy.Id
        Write-Host "[SUCCESS] Auto-assignment policy created successfully: ID $policyId" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to create auto-assignment policy." -ForegroundColor Red
        return
    }
}



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT SUMMARY: RESOURCE DEPLOYMENT CONFIRMATION
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Green
Write-Host "│                   FINAL SUCCESS MESSAGE                    │" -ForegroundColor Green
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Green
Write-Host ""

# --- Create structured output for better auditability ---
# Using PSCustomObject for proper object-oriented reporting
# Following Azure best practice for auditable deployment reporting
$finalOutput = @(
    [PSCustomObject]@{ 
        "Property" = "Access Package ID      ";  # Entitlement resource identifier
        "DisplayName    " = $accessPackageName ; # User-friendly name for package
        "Value" = $accessPackageId             # Unique GUID for API references
    },
    [PSCustomObject]@{ 
        "Property" = "Policy ID             ";  # Auto-assignment policy reference
        "DisplayName    " = $autoPolicyName ;   # Policy friendly name
        "Value" = $policyId                     # Policy GUID for future reference
    },
    [PSCustomObject]@{ 
        "Property" = "Access Package Catalog      "; # Container for access packages
        "DisplayName    " = $catalogName ;         # Catalog friendly name
        "Value" = $catalogId                       # Catalog GUID for API operations
    },
    [PSCustomObject]@{ 
        "Property" = "Entra ID Role      ";      # Privileged role reference
        "DisplayName    " = $Role.DisplayName ;  # Human-readable role name
        "Value" = $Role.Id                       # Role GUID for IAM operations
    }
)

# --- Display results with enhanced formatting for readability ---
# Using Format-Table for consistent columnar output
# This follows Azure best practice for administrative reporting
$finalOutput | Format-Table

# --- Overall success confirmation with colored feedback ---
# Using ForegroundColor Green to clearly indicate successful completion
# This follows Azure best practice for visual status indication
Write-Host "`n[SUCCESS] Access Package, Assignment Policy, and Access Package Catalog was created!" -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────
# POST-DEPLOYMENT INSTRUCTIONS: USER INVITATION ACCEPTANCE WORKFLOW
# ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "                     ⚠️  IMPORTANT INFORMATION  ⚠️"                  -ForegroundColor Yellow
Write-Host "══════════════════════════════════════════════════════════════════════"  -ForegroundColor DarkYellow

# --- Critical next steps for administrators ---
# Highlighting information that requires follow-up action
# Following Azure best practice for clear post-deployment instructions
Write-Host "     Please ensure that the guest invitations sent via email are      "  -ForegroundColor Yellow
Write-Host "     accepted by the recipients. This step is required to enable      "  -ForegroundColor Yellow
Write-Host "     access to the resources and functionality provided by the        "  -ForegroundColor Yellow
Write-Host "     access package.                                                  "  -ForegroundColor Yellow
Write-Host ""

# --- User experience expectations and portal reference ---
# Providing end-user information for onboarding guidance
# Following Azure best practice for end-user documentation
Write-Host "     Once the invitation is accepted, users will be able to see       "  -ForegroundColor Gray
Write-Host "     and access the assigned resources in their My Apps portal:       "  -ForegroundColor Gray
Write-Host "     https://myapplications.microsoft.com                            "  -ForegroundColor Cyan
Write-Host ""

# --- Process clarification to prevent unnecessary troubleshooting ---
# Setting correct expectations for access timing
# This aligns with Azure best practice for change management communication
Write-Host "     This is expected behavior and does not require troubleshooting. "  -ForegroundColor Gray
Write-Host "══════════════════════════════════════════════════════════════════════"  -ForegroundColor DarkYellow
Write-Host ""

# --- Final script completion message ---
# Clear indication that automation has successfully completed
# Following Azure best practice for automation completion notification
Write-Host "`n[SUCCESS] Script finished." -ForegroundColor Green

# Brief pause for message visibility before exit prompt
# This ensures critical information isn't immediately dismissed
Start-Sleep -Seconds 1

# Interactive exit to allow reading output before closing
# Following Azure best practice for interactive scripts
Read-Host "Press any key to exit"