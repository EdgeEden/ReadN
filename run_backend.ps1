Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Starting ReadN FastAPI Backend Server..." -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

Set-Location -Path "$PSScriptRoot\backend"
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

