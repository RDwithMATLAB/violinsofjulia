#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "src\Publication_Grade_Statistics.jl"

if (-not (Test-Path $scriptPath)) {
    throw "Julia source not found: $scriptPath"
}

if (-not (Get-Command julia -ErrorAction SilentlyContinue)) {
    throw "Julia was not found in PATH. Run .\install.ps1 after installing Julia 1.9+."
}

julia --project=$PSScriptRoot $scriptPath
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
