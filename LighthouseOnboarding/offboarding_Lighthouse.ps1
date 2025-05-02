# 1) Sign in
Connect-AzAccount | Out-Null

# 2) Offboard each enabled subscription
Get-AzSubscription | Where-Object State -EQ 'Enabled' | ForEach-Object {
    $subId   = $_.Id
    $subName = $_.Name

    Write-Host "`n== Offboarding $subName ($subId)" -ForegroundColor Cyan
    Set-AzContext -SubscriptionId $subId -ErrorAction Stop

    #
    # 2a) Remove any assignments
    #
    $assigns = Get-AzManagedServicesAssignment -Scope "/subscriptions/$subId" -ErrorAction SilentlyContinue
    if ($assigns) {
        foreach ($a in $assigns) {
            Write-Host "Removing assignment: $($a.Name)" -ForegroundColor Yellow
            Remove-AzManagedServicesAssignment `
              -Name   $a.Name `
              -Scope  "/subscriptions/$subId" `
              -Confirm:$false
        }
    }
    else {
        Write-Host "No assignment found." -ForegroundColor DarkGray
    }

    #
    # 2b) Remove any definitions
    #
    $defs = Get-AzManagedServicesDefinition -Scope "/subscriptions/$subId" -ErrorAction SilentlyContinue
    if ($defs) {
        foreach ($d in $defs) {
            Write-Host "Removing definition: $($d.Name)" -ForegroundColor Yellow
            Remove-AzManagedServicesDefinition `
              -Name   $d.Name `
              -Scope  "/subscriptions/$subId" `
              -Confirm:$false
        }
    }
    else {
        Write-Host "No definition found." -ForegroundColor DarkGray
    }

    #
    # 2c) Verify cleanup
    #
    $stillA = Get-AzManagedServicesAssignment   -Scope "/subscriptions/$subId" -ErrorAction SilentlyContinue
    $stillD = Get-AzManagedServicesDefinition   -Scope "/subscriptions/$subId" -ErrorAction SilentlyContinue

    if (-not $stillA -and -not $stillD) {
        Write-Host "✅ Successfully offboarded $subName." -ForegroundColor Green
    }
    else {
        Write-Host "❌ Offboarding incomplete for $subName :" -ForegroundColor Red
        if ($stillA) { Write-Host "  • Assignments still present: $($stillA.Name -join ', ')" }
        if ($stillD) { Write-Host "  • Definitions still present: $($stillD.Name -join ', ')" }
    }
}

Write-Host "`n🎉 Offboarding run complete." -ForegroundColor Cyan
