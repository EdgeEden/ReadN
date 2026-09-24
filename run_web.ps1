Write-Host "=========================================" -ForegroundColor Green
Write-Host "Launching ReadN Flutter Web in Chrome..." -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

Set-Location -Path "$PSScriptRoot\frontend"
flutter run -d chrome --web-port 3000

