$ErrorActionPreference = 'Continue'

$savedDir = Get-Location
$ahkDir = "$env:USERPROFILE\.claude"

Write-Host "Switching to $ahkDir" -ForegroundColor Cyan
Set-Location $ahkDir

Write-Host "Running git add -A..." -ForegroundColor Cyan
git add -A
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: git add failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    Set-Location $savedDir
    exit 1
}

$files = git diff --cached --name-only
if ($files) {
    $msg = "update " + (($files | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join ", ")
} else {
    $msg = "update"
}
Write-Host "Running git commit: $msg" -ForegroundColor Cyan
git commit -m $msg
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: git commit exited with code $LASTEXITCODE (nothing to commit?)" -ForegroundColor Yellow
}

Write-Host "Running git push..." -ForegroundColor Cyan
git push
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: git push failed (exit code $LASTEXITCODE)" -ForegroundColor Red
    Set-Location $savedDir
    exit 1
}

Write-Host "Done! Returning to $savedDir" -ForegroundColor Green
Set-Location $savedDir
