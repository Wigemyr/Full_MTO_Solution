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
$groupName = "PIM - Security Admin Group" # Name for the PIM-enabled group
$groupDescription = "PIM-enabled group for Security Administrator role assignment" # Description for the group
$roleDisplayName = "Security Administrator" # Role to be assigned to the group

# Hardcoded employeeId
$expectedEmployeeId = "n38fy345gf54" # Example employeeId to be assigned to users

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


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# PowerShell Version Check (Requires 7+)
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                  CHECK POWERSHELL VERSION                  │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] This script requires PowerShell 7 or later." -ForegroundColor Yellow

# Wrap the version‐check pause in our spinner so it lasts at least 2 seconds:
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
# CHECK & INSTALL REQUIRED MODULES
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│              CHECK & INSTALL REQUIRED MODULES              │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

$requiredModules = @("Microsoft.Graph")

foreach ($module in $requiredModules) {
    # 1) Always spin ≥2s while checking, using $using:module so it's not null:
    $isInstalled = Invoke-WithSpinner -ScriptBlock {
        # $using:module is injected into the background job
        if (Get-Module -ListAvailable -Name $using:module) { $true } else { $false }
    } -MinimumMilliseconds 1000

    if ($isInstalled) {
        Write-Host "[INFO] Module '$module' is already installed." -ForegroundColor Green
        continue
    }

    Write-Host "[WARNING] Module '$module' not found." -ForegroundColor Yellow
    $ans = Read-Host "    Install '$module' now? (Y/N)"
    if ($ans -notmatch '^[Yy]') {
        Write-Host "[ERROR] Module '$module' is required. Exiting." -ForegroundColor Red
        exit 1
    }

    # 2) Spin ≥2s while installing, again passing $using:module
    Invoke-WithSpinner -ScriptBlock {
        Install-Module $using:module -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } -MinimumMilliseconds 1000 | Out-Null

    Write-Host "[SUCCESS] Module '$module' installed successfully!" -ForegroundColor Green
}


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
    # show spinner for at least 2 s while Connect-MgGraph runs
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
# CHECK IF USER IS GLOBAL ADMINISTRATOR
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│            CHECK FOR CORRECT ROLE TO RUN SCRIPT            │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

$requiredRole = "Global Administrator"
Write-Host "[INFO] Checking if user is '$requiredRole'..." -ForegroundColor Cyan

# spin ≥2s while we grab context, user and role-membership info
$authInfo = Invoke-WithSpinner -ScriptBlock {
    $upn     = (Get-MgContext).Account
    $user    = Get-MgUser -UserId $upn
    $role    = Get-MgDirectoryRole -All | Where-Object { $_.DisplayName -eq $using:requiredRole }
    $members = if ($role) { Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All } else { @() }

    [pscustomobject]@{
        UPN     = $upn
        UserId  = $user.Id
        Role    = $role
        Members = $members
    }
} -MinimumMilliseconds 1000

# clear that spinner line
Write-Host "`r[2K" -NoNewline

# now evaluate
if (-not $authInfo.Role) {
    Write-Host "[ERROR] The role '$requiredRole' is not enabled in your tenant." -ForegroundColor Red
    exit 1
}

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
# ADD PIM GROUP WITH ACTIVE ROLE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│               ADD PIM GROUP WITH ACTIVE ROLE               │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# (Make sure these are set before you run this block:)
#   $groupName
#   $groupDescription
#   $roleDisplayName

# --- Step 1: Check if the PIM group already exists (2 s spinner) ---
$pimGroup = Invoke-WithSpinner -ScriptBlock {
    Get-MgGroup -All | Where-Object DisplayName -eq $using:groupName
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($pimGroup) {
    Write-Host "[INFO]    PIM group '$groupName' already exists. Skipping creation." -ForegroundColor Yellow
}
else {
    # --- Step 1b: Create the group (2 s spinner) ---
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

    Write-Host "`r[2K" -NoNewline
    Write-Host "[SUCCESS] Created PIM group: $($pimGroup.DisplayName)" -ForegroundColor Green
}

# Extract the plain Id for threaded calls
$pimGroupId = $pimGroup.Id

# --- Step 2: Find or enable the Security Administrator role (2 s spinner) ---
$role = Invoke-WithSpinner -ScriptBlock {
    $r = Get-MgDirectoryRole | Where-Object DisplayName -eq $using:roleDisplayName
    if (-not $r) {
        $t = Get-MgDirectoryRoleTemplate | Where-Object DisplayName -eq $using:roleDisplayName
        if ($t) { Enable-MgDirectoryRole -RoleTemplateId $t.Id | Out-Null }
        Start-Sleep -Seconds 5
        $r = Get-MgDirectoryRole | Where-Object DisplayName -eq $using:roleDisplayName
    }
    return $r
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if (-not $role) {
    Write-Host "[ERROR] Could not find or enable role '$roleDisplayName'." -ForegroundColor Red
    exit 1
}

# Extract the plain Id for threaded calls
$roleId = $role.Id

# --- Step 3: Assign the group if not already a member (2 s spinner) ---
$alreadyAssigned = Invoke-WithSpinner -ScriptBlock {
    (Get-MgDirectoryRoleMember -DirectoryRoleId $using:roleId -All).Id -contains $using:pimGroupId
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($alreadyAssigned) {
    Write-Host "[INFO]    Group '$groupName' is already assigned to '$roleDisplayName'. Skipping..." -ForegroundColor Yellow
}
else {
    # --- Step 3b: Perform the assignment (2 s spinner) ---
    Invoke-WithSpinner -ScriptBlock {
        $body = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$using:pimGroupId" }
        New-MgDirectoryRoleMemberByRef -DirectoryRoleId $using:roleId -BodyParameter $body
    } -MinimumMilliseconds 1000 | Out-Null

    Write-Host "`r[2K" -NoNewline
    Write-Host "[SUCCESS] Assigned role '$roleDisplayName' to group: $groupName" -ForegroundColor Green
}






# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# INVITE GUEST USER FROM MAIN TENANT
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│             INVITE GUEST USER FROM MAIN TENANT             │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Starting invitation process..." -ForegroundColor Cyan

# Load the CSV normally—this is usually fast, so no spinner here
$guestList = Import-Csv -Path $pathToCSV

# Prepare results array
$results = @()

foreach ($guest in $guestList) {
    $displayName    = $guest.DisplayName
    $mainAdminEmail = $guest.Email
    $employeeId     = $guest.EmployeeId

    # --- Check if the guest exists (1s spinner) ---
    $existingGuest = Invoke-WithSpinner -ScriptBlock {
        Get-MgUser -Filter "mail eq '$using:mainAdminEmail'" -ConsistencyLevel eventual -ErrorAction Stop
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    if ($existingGuest) {
        $results += [PSCustomObject]@{
            "User Principal Name" = $mainAdminEmail
            "Object ID"           = $existingGuest.Id
            "Status"              = "Guest already exists. Skipping invitation."
        }
        continue
    }

    # --- Invite the guest (1s spinner) ---
    $invitation = Invoke-WithSpinner -ScriptBlock {
        New-MgInvitation `
            -InvitedUserDisplayName    $using:displayName `
            -InvitedUserEmailAddress   $using:mainAdminEmail `
            -InviteRedirectUrl         "https://myapplications.microsoft.com" `
            -SendInvitationMessage:$true
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    if ($invitation) {
        $results += [PSCustomObject]@{
            "User Principal Name" = $mainAdminEmail
            "Object ID"           = $invitation.InvitedUser.Id
            "Status"              = "Invitation sent, and user created."
        }
    } else {
        $results += [PSCustomObject]@{
            "User Principal Name" = $mainAdminEmail
            "Object ID"           = "N/A"
            "Status"              = "Failed to invite."
        }
    }
}

# Display results
Write-Host ""
$results | Format-Table `
    @{Label="User Principal Name"; Expression={$_. "User Principal Name".PadRight(50)} }, `
    @{Label="Object ID";           Expression={$_. "Object ID".PadRight(40)} }, `
    @{Label="Status";              Expression={$_. "Status".PadRight(60)} } -AutoSize

Start-Sleep -Seconds 2



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# ADD STRING TO EMPLOYEE ID FILTER FOR ACCESS PACKAGE ASSIGNMENT
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│              ADD STRING TO EMPLOYEE ID FILTER              │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

# Import users from CSV
$users   = Import-Csv -Path $pathToCSV
$results = @()

foreach ($user in $users) {
    $displayName = $user.DisplayName
    $email       = $user.Email

    Write-Host "`nProcessing $email ..." -ForegroundColor Cyan

    # --- Step A: Find the user (spinner only while the call runs, min 1s) ---
    $guest = $null
    for ($attempt = 1; $attempt -le $retryCount; $attempt++) {
        try {
            $guest = Invoke-WithSpinner -ScriptBlock {
                Get-MgUser -Filter "mail eq '$using:email'" -ConsistencyLevel eventual -ErrorAction Stop
            } -MinimumMilliseconds 1000
            Write-Host "`r[2K" -NoNewline

            if ($guest) { break }
            Write-Host "[INFO] User not found yet (Attempt $attempt/$retryCount)." -ForegroundColor Yellow
            Start-Sleep -Seconds $retryDelaySeconds
        } catch {
            Write-Host "`r[2K" -NoNewline
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
        # --- Step B: Fetch current employeeId (spinner only while the call runs, min 1s) ---
        $currentEmployeeId = Invoke-WithSpinner -ScriptBlock {
            Get-MgUser -UserId $using:guestId -Property "employeeId" |
                Select-Object -ExpandProperty employeeId
        } -MinimumMilliseconds 1000
        Write-Host "`r[2K" -NoNewline

        if ($currentEmployeeId -eq $expectedEmployeeId) {
            $status = "Already correct"
            Write-Host "[INFO] Skipping update – employeeId already set to $expectedEmployeeId" -ForegroundColor Yellow
        } else {
            # --- Step C: Update employeeId (spinner only while the call runs, min 1s) ---
            Invoke-WithSpinner -ScriptBlock {
                Update-MgUser -UserId $using:guestId -BodyParameter @{ employeeId = $using:expectedEmployeeId }
            } -MinimumMilliseconds 1000 | Out-Null
            Write-Host "`r[2K" -NoNewline

            # --- Step D: Verify update (spinner only while the call runs, min 1s) ---
            $updatedEmployeeId = Invoke-WithSpinner -ScriptBlock {
                Get-MgUser -UserId $using:guestId -Property "employeeId" |
                    Select-Object -ExpandProperty employeeId
            } -MinimumMilliseconds 1000
            Write-Host "`r[2K" -NoNewline

            if ($updatedEmployeeId -eq $expectedEmployeeId) {
                $status = "Updated to $expectedEmployeeId"
                Write-Host "[SUCCESS] Updated employeeId to $expectedEmployeeId for $email" -ForegroundColor Green
            } else {
                $status = "Update failed"
                Write-Host "[WARNING] employeeId not updated for $email" -ForegroundColor Yellow
            }
        }

        # Log result
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

# Display summary table
Write-Host ""
$results | Format-Table `
    @{Label="DisplayName";           Expression={ $_.DisplayName.PadRight(35) }}, `
    @{Label="Email";                 Expression={ $_.Email.PadRight(55) }}, `
    @{Label="Employee ID Status";    Expression={ $_.EmployeeIdStatus.PadRight(30) }}, `
    @{Label="Overall Status";        Expression={ $_.OverallStatus } }



# ─────────────────────────────────────────────────────────────────────────────
# IMPORTANT MESSAGE BEFORE PROCEEDING
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

# instead of Start-Sleep, prompt the user to continue when they're done reading
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
Write-Host "`r[2K" -NoNewline

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
    Write-Host "`r[2K" -NoNewline

    $catalogId = $newCatalog.Id
    Write-Host "[SUCCESS] Created catalog '$catalogName'. ID: $catalogId" -ForegroundColor Green
}



# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# CREATE OR FIND ACCESS PACKAGE
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│               CREATE OR FIND ACCESS PACKAGE                │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""

Write-Host "[INFO] Checking for existing Access Package: '$accessPackageName'..." -ForegroundColor Cyan

# --- Spinner while fetching all packages, then filter client-side ---
$allPackages = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementAccessPackage -All
} -MinimumMilliseconds 1000
# clear spinner line
Write-Host "`r[2K" -NoNewline

$existingPackage = $allPackages |
    Where-Object DisplayName -eq $accessPackageName |
    Select-Object -First 1

if ($existingPackage) {
    $accessPackageId = $existingPackage.Id
    Write-Host "[SUCCESS] Found existing Access Package: '$accessPackageName' (ID: $accessPackageId)" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Creating new Access Package: '$accessPackageName'..." -ForegroundColor Yellow

    $params = @{
        displayName = $accessPackageName
        description = $accessPackageDescription
        isHidden    = $false
        catalog     = @{ id = $catalogId }
    }

    # --- Spinner while creating the package ---
    $accessPackage = Invoke-WithSpinner -ScriptBlock {
        New-MgEntitlementManagementAccessPackage -BodyParameter $using:params
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    $accessPackageId = $accessPackage.Id
    Write-Host "[SUCCESS] Created Access Package: '$accessPackageName' (ID: $accessPackageId)" -ForegroundColor Green
}


# ──────────────────────────────────────────────────────────────────────────────
# ADD PIM GROUP WITH ROLE TO CATALOG
# ──────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "┌────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│             ADD PIM GROUP WITH ROLE TO CATALOG             │" -ForegroundColor Cyan
Write-Host "└────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
Write-Host ""


$GroupObjectId = $pimGroup.Id

# 1) check for existing
$exists = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResource `
      -AccessPackageCatalogId $using:catalogId `
      -Filter "originId eq '$using:GroupObjectId' and originSystem eq 'AadGroup'"
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($exists) {
    Write-Host "[INFO] Already in catalog. Skipping." -ForegroundColor Yellow
    return
}

# 2) add it
Write-Host "[INFO] Adding group to catalog…" -ForegroundColor Cyan
Invoke-WithSpinner -ScriptBlock {
    New-MgEntitlementManagementResourceRequest `
      -RequestType 'adminAdd' `
      -Resource @{ originId     = $using:GroupObjectId
                   originSystem = 'AadGroup' } `
      -Catalog  @{ id = $using:catalogId }
} -MinimumMilliseconds 1000 | Out-Null
Write-Host "`r[2K" -NoNewline

# 3) verify
$valid = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResource `
      -AccessPackageCatalogId $using:catalogId `
      -Filter "originId eq '$using:GroupObjectId' and originSystem eq 'AadGroup'"
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

if ($valid) {
    Write-Host "[SUCCESS] Group successfully added to catalog." -ForegroundColor Green
} else {
    Write-Host "[WARNING] Could not verify – please check manually." -ForegroundColor Yellow
}



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
$catalogResources = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResource `
      -AccessPackageCatalogId $using:catalogId `
      -ExpandProperty "scopes" -All
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

$groupResource = $catalogResources | Where-Object OriginId -eq $pimGroup.Id
if (-not $groupResource) {
    Write-Host "[ERROR] Group not found in catalog!" -ForegroundColor Red
    return
}

$groupResourceScope = $groupResource.Scopes[0]

# 2. Get the 'Member' role for the group
$filter = "(originSystem eq 'AadGroup' and resource/id eq '$($groupResource.Id)')"
$resourceRoles = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementCatalogResourceRole `
      -AccessPackageCatalogId $using:catalogId `
      -Filter $using:filter `
      -ExpandProperty "resource"
} -MinimumMilliseconds 1000
Write-Host "`r[2K" -NoNewline

$memberRole = $resourceRoles | Where-Object DisplayName -eq "Member"
if (-not $memberRole) {
    Write-Host "[ERROR] 'Member' role not found for the group resource." -ForegroundColor Red
    return
}

# 3. Construct body for assignment
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

# 4. Assign group to access package
try {
    Write-Host "[INFO] Linking group to access package..." -ForegroundColor Yellow
    Invoke-WithSpinner -ScriptBlock {
        New-MgEntitlementManagementAccessPackageResourceRoleScope `
          -AccessPackageId $using:accessPackageId `
          -BodyParameter $using:body
    } -MinimumMilliseconds 1000 | Out-Null
    Write-Host "`r[2K" -NoNewline
    Write-Host "[SUCCESS] Linked group to access package with 'Member' role." -ForegroundColor Green
}
catch {
    Write-Host "`r[2K" -NoNewline
    Write-Host "[ERROR] Failed to link group to access package: $_" -ForegroundColor Red
    Write-Host "[INFO] Request payload:" -ForegroundColor Yellow
    $body | ConvertTo-Json -Depth 10 | Write-Host
}



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

Write-Host "[INFO] Checking for existing assignment policies..." -ForegroundColor Cyan

# 1) Fetch all policies under spinner
$allPolicies = Invoke-WithSpinner -ScriptBlock {
    Get-MgEntitlementManagementAssignmentPolicy -All
} -MinimumMilliseconds 1000
# clear spinner line
Write-Host "`r[2K" -NoNewline

# 2) Find by name
$existingPolicy = $allPolicies | Where-Object DisplayName -eq $autoPolicyName

if ($existingPolicy) {
    $policyId = $existingPolicy.Id
    Write-Host "[SUCCESS] Found existing Assignment Policy '$autoPolicyName'. Skipping creation." -ForegroundColor Yellow
}
else {
    Write-Host "[INFO] Creating new auto-assignment policy: '$autoPolicyName'..." -ForegroundColor Cyan

    # 🛠 Build request body
    $autoPolicyParameters = @{
        displayName            = $autoPolicyName
        description            = $autoPolicyDescription
        allowedTargetScope     = "specificDirectoryUsers"
        specificAllowedTargets = @(
            @{
                "@odata.type"   = "#microsoft.graph.attributeRuleMembers"
                description     = $policyDescription
                membershipRule  = $employeeIdFilter
            }
        )
        automaticRequestSettings = @{
            requestAccessForAllowedTargets = $true
        }
        accessPackage = @{ id = $accessPackageId }
    }

    # 3) Create under spinner
    $newPolicy = Invoke-WithSpinner -ScriptBlock {
        New-MgEntitlementManagementAssignmentPolicy -BodyParameter $using:autoPolicyParameters
    } -MinimumMilliseconds 1000
    # clear spinner line
    Write-Host "`r[2K" -NoNewline

    if ($newPolicy) {
        $policyId = $newPolicy.Id
        Write-Host "[SUCCESS] Auto-assignment policy created successfully: ID $policyId" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to create auto-assignment policy." -ForegroundColor Red
        return
    }
}



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