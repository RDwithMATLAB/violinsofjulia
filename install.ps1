#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host "Publication-Grade Statistics - Installer" -ForegroundColor Cyan

if (-not (Get-Command julia -ErrorAction SilentlyContinue)) {
    throw "Julia was not found in PATH. Install Julia 1.9+ and restart PowerShell."
}

julia --version
julia --project=. -e 'using Pkg; Pkg.instantiate()'

Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Run: .\run_pipeline.ps1" -ForegroundColor Cyan
