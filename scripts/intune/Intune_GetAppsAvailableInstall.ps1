Connect-MgGraph

Write-Host "Retrieving Intune applications..." -ForegroundColor Cyan

$apps = Get-MgDeviceAppManagementMobileApp

$totalApps = $apps.Count
$currentApp = 0
$results = @()

# Cache groups so we don't repeatedly query the same Group ID
$groupCache = @{}

Write-Host "Found $totalApps applications." -ForegroundColor Green

foreach ($app in $apps) {

    $currentApp++

    Write-Progress `
        -Activity "Scanning Intune Applications" `
        -Status "$currentApp of $totalApps - $($app.DisplayName)" `
        -PercentComplete (($currentApp / $totalApps) * 100)

    Write-Host "[$currentApp/$totalApps] Processing: $($app.DisplayName)"

    try {

        $assignments = Invoke-MgGraphRequest `
            -Method GET `
            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.Id)/assignments"

        foreach ($assignment in $assignments.value) {

            $groupId = $assignment.target.groupId

            $groupName = "N/A"

            if ($groupId) {

                if (-not $groupCache.ContainsKey($groupId)) {

                    try {
                        $group = Get-MgGroup -GroupId $groupId -ErrorAction Stop

                        $groupCache[$groupId] = $group.DisplayName
                    }
                    catch {
                        $groupCache[$groupId] = "Unknown Group"
                    }
                }

                $groupName = $groupCache[$groupId]
            }

            # Only show Available apps
            if ($assignment.intent -eq "available") {

                Write-Host "  -> Available assignment: $groupName" -ForegroundColor Yellow

                $results += [PSCustomObject]@{
                    AppName        = $app.DisplayName
                    AppId          = $app.Id
                    AppType        = $app.'@odata.type'
                    AssignmentType = $assignment.intent
                    GroupName      = $groupName
                    GroupId        = $groupId
                }
            }
        }
    }
    catch {
        Write-Warning "Failed processing $($app.DisplayName): $_"
    }
}

Write-Progress -Activity "Scanning Intune Applications" -Completed

Write-Host ""
Write-Host "Finished scanning all applications." -ForegroundColor Green
Write-Host "Available assignments found: $($results.Count)" -ForegroundColor Green

$csvPath = ".\Intune-Available-Apps.csv"

$results |
    Sort-Object AppName, GroupName |
    Export-Csv -Path $csvPath -NoTypeInformation

Write-Host ""
Write-Host "CSV exported to $csvPath" -ForegroundColor Cyan

$results | Format-Table -AutoSize