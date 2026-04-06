# Remove "nul" file from a given directory before packing.
# Based on scripts/win-safety/remove-nul.ps1
#
# On Windows, "nul" is a reserved device name. Standard commands CANNOT delete it.
# The ONLY safe method: [System.IO.File]::Delete('\\?\<full-path>\nul')
#
# WARNING: NEVER use del, Remove-Item, rm, or wildcards for this!

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDir
)

$TargetDir = (Resolve-Path $TargetDir).Path
$uncPath = "\\?\$TargetDir\nul"

if ([System.IO.File]::Exists($uncPath)) {
    $bytes = [System.IO.File]::ReadAllBytes($uncPath)
    Write-Host "WARNING: Found 'nul' file ($($bytes.Length) bytes) in $TargetDir" -ForegroundColor Yellow
    [System.IO.File]::Delete($uncPath)

    if ([System.IO.File]::Exists($uncPath)) {
        Write-Host "ERROR: Failed to delete nul file!" -ForegroundColor Red
        exit 1
    }
    Write-Host "Removed 'nul' file successfully." -ForegroundColor Green
} else {
    Write-Host "No 'nul' file found - OK." -ForegroundColor Green
}
