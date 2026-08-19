<#
.SYNOPSIS
    Resolves device display names from a CSV to their Entra ID object IDs.

.DESCRIPTION
    Reads a CSV containing a DeviceName column, looks up each device in Entra ID
    via Microsoft Graph, and exports the results with the matching object ID.
    Reports live progress, handles lookup failures per-row, and prints a summary.

    If InputPath and OutputPath are not supplied, the script prompts for them.

.EXAMPLE
    .\Get-DeviceObjectIds.ps1
    Prompts for the input and output file paths.

.EXAMPLE
    .\Get-DeviceObjectIds.ps1 -InputPath C:\temp\devices.csv -OutputPath C:\temp\out.csv
    Runs unattended with no prompts.

.NOTES
    Requires the Microsoft.Graph.Identity.DirectoryManagement module.
#>

[CmdletBinding()]
param(
    # Leave these empty to be prompted at run time. Supply them on the command
    # line instead if you want to run the script unattended.
    [string]$InputPath,
    [string]$OutputPath,

    # How often to write a line to the console, in addition to the progress bar.
    [int]$UpdateInterval = 25
)

$ErrorActionPreference = 'Stop'

# --- Helper: prompt, accepting a default on empty input --------------------
function Read-PathPrompt {
    param(
        [string]$Prompt,
        [string]$Default
    )
    $Label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $Entry = Read-Host $Label
    if ([string]::IsNullOrWhiteSpace($Entry)) { return $Default }
    # Strip quotes so a path pasted from "Copy as path" still works
    return $Entry.Trim().Trim('"')
}

# --- Input path: keep asking until we get a file that exists ---------------
$DefaultInput = "C:\temp\devices.csv"

while ($true) {
    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $InputPath = Read-PathPrompt -Prompt "Path to the input CSV" -Default $DefaultInput
    }
    if (Test-Path -Path $InputPath -PathType Leaf) { break }

    Write-Warning "File not found: $InputPath"
    $InputPath = $null
}

$InputPath = (Resolve-Path -Path $InputPath).Path

$CSVData = @(Import-Csv -Path $InputPath)

if ($CSVData.Count -eq 0) {
    throw "Input file '$InputPath' contains no rows."
}

if (-not ($CSVData[0].PSObject.Properties.Name -contains 'DeviceName')) {
    throw "Input file '$InputPath' has no 'DeviceName' column. Found: $($CSVData[0].PSObject.Properties.Name -join ', ')"
}

Write-Host "Loaded $($CSVData.Count) row(s) from $InputPath" -ForegroundColor Cyan

# --- Output path: default alongside the input file -------------------------
$DefaultOutput = Join-Path -Path (Split-Path -Path $InputPath -Parent) `
                           -ChildPath ("{0}-with-objectids.csv" -f [IO.Path]::GetFileNameWithoutExtension($InputPath))

while ($true) {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Read-PathPrompt -Prompt "Path for the output CSV" -Default $DefaultOutput
    }

    # A bare filename lands in the current directory
    $OutputDir = Split-Path -Path $OutputPath -Parent
    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir  = (Get-Location).Path
        $OutputPath = Join-Path -Path $OutputDir -ChildPath $OutputPath
    }

    if (-not (Test-Path -Path $OutputDir -PathType Container)) {
        Write-Warning "Folder does not exist: $OutputDir"
        $OutputPath = $null
        continue
    }

    $AlreadyExists = Test-Path -Path $OutputPath -PathType Leaf
    if ($AlreadyExists -and (Read-Host "'$OutputPath' already exists. Overwrite? (y/n)") -notmatch '^(y|yes)$') {
        $OutputPath = $null
        continue
    }

    # Check writability now rather than after a long run (e.g. file open in Excel)
    try {
        [IO.File]::Open($OutputPath, 'OpenOrCreate', 'Write').Close()
        if (-not $AlreadyExists) { Remove-Item -Path $OutputPath -Force }
        break
    }
    catch {
        Write-Warning "Cannot write to '$OutputPath': $($_.Exception.Message)"
        $OutputPath = $null
    }
}

# --- Connect (only if not already connected) ------------------------------
if (-not (Get-MgContext)) {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Device.Read.All" | Out-Null
}
Write-Host "Connected as: $((Get-MgContext).Account)" -ForegroundColor Cyan
Write-Host "Processing $($CSVData.Count) device(s) from $InputPath`n" -ForegroundColor Cyan

# --- Process --------------------------------------------------------------
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$Counter   = 0
$Stats     = @{ Found = 0; NotFound = 0; Duplicate = 0; Error = 0 }

$Results = foreach ($Row in $CSVData) {

    $Counter++
    $Name = $Row.DeviceName

    # Estimate remaining time from the average so far
    $AvgSeconds = if ($Counter -gt 1) { $Stopwatch.Elapsed.TotalSeconds / ($Counter - 1) } else { 0 }
    $Remaining  = [int]($AvgSeconds * ($CSVData.Count - $Counter + 1))

    Write-Progress -Activity "Resolving device object IDs" `
                   -Status  "[$Counter of $($CSVData.Count)] $Name" `
                   -PercentComplete (($Counter / $CSVData.Count) * 100) `
                   -SecondsRemaining $Remaining

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Stats.Error++
        Write-Warning "Row ${Counter}: DeviceName is blank - skipping."
        [PSCustomObject]@{ DeviceName = $Name; ObjectID = $null; Status = 'Error'; Detail = 'Blank device name' }
        continue
    }

    # Single quotes must be doubled to be valid inside an OData string literal
    $SafeName = $Name -replace "'", "''"

    try {
        $Devices = @(Get-MgDevice -Filter "displayName eq '$SafeName'" -Property "id","displayName" -All -ErrorAction Stop)

        switch ($Devices.Count) {
            0 {
                $Stats.NotFound++
                Write-Warning "Not found in Entra ID: $Name"
                [PSCustomObject]@{ DeviceName = $Name; ObjectID = $null; Status = 'NotFound'; Detail = $null }
            }
            1 {
                $Stats.Found++
                [PSCustomObject]@{ DeviceName = $Name; ObjectID = $Devices[0].Id; Status = 'Found'; Detail = $null }
            }
            default {
                # Multiple devices share this display name - emit one row each so nothing is lost
                $Stats.Duplicate++
                Write-Warning "$($Devices.Count) devices share the name '$Name' - all returned."
                foreach ($Device in $Devices) {
                    [PSCustomObject]@{ DeviceName = $Name; ObjectID = $Device.Id; Status = 'Duplicate'; Detail = "$($Devices.Count) matches" }
                }
            }
        }
    }
    catch {
        $Stats.Error++
        Write-Warning "Lookup failed for '$Name': $($_.Exception.Message)"
        [PSCustomObject]@{ DeviceName = $Name; ObjectID = $null; Status = 'Error'; Detail = $_.Exception.Message }
    }

    if ($UpdateInterval -gt 0 -and $Counter % $UpdateInterval -eq 0) {
        Write-Host ("  ...{0}/{1} processed ({2:N0}%) - {3} found, {4} not found" -f `
            $Counter, $CSVData.Count, (($Counter / $CSVData.Count) * 100), $Stats.Found, $Stats.NotFound) -ForegroundColor DarkGray
    }
}

Write-Progress -Activity "Resolving device object IDs" -Completed
$Stopwatch.Stop()

# --- Export ---------------------------------------------------------------
$Results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

# --- Summary --------------------------------------------------------------
Write-Host "`n--- Summary ---" -ForegroundColor Green
Write-Host ("Rows processed : {0}" -f $CSVData.Count)
Write-Host ("Found          : {0}" -f $Stats.Found)      -ForegroundColor Green
Write-Host ("Not found      : {0}" -f $Stats.NotFound)   -ForegroundColor $(if ($Stats.NotFound) { 'Yellow' } else { 'Gray' })
Write-Host ("Duplicate name : {0}" -f $Stats.Duplicate)  -ForegroundColor $(if ($Stats.Duplicate) { 'Yellow' } else { 'Gray' })
Write-Host ("Errors         : {0}" -f $Stats.Error)      -ForegroundColor $(if ($Stats.Error) { 'Red' } else { 'Gray' })
Write-Host ("Elapsed        : {0:hh\:mm\:ss}" -f $Stopwatch.Elapsed)
Write-Host "`nExport completed to $OutputPath" -ForegroundColor Green