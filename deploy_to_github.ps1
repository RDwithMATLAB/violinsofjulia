#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy the Publication-Grade Statistics Pipeline to GitHub.

.DESCRIPTION
    Initializes the local Git repository if necessary, stages all files,
    commits them, configures the origin remote, and pushes main.

    This version avoids `git remote get-url origin` because that command
    returns an error when origin does not yet exist.

.PARAMETER RepoUrl
    GitHub repository URL.

.PARAMETER CommitMessage
    Commit message.

.PARAMETER Force
    If specified, use --force-with-lease when pushing.
#>

param (
    [string]$RepoUrl = "https://github.com/RDwithMATLAB/violinsofjulia.git",
    [string]$CommitMessage = "Update: Publication-Grade Statistics Pipeline",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Scientific Pipeline: Automated GitHub Deployment" -ForegroundColor Green
Write-Host " User: RDwithMATLAB" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# ----------------------------------------------------------------------
# 1. Verify Git
# ----------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is not detected in PATH. Install Git and restart PowerShell."
}

Write-Host "`nGit detected:" -ForegroundColor Yellow
git --version

# ----------------------------------------------------------------------
# 2. Confirm repository URL
# ----------------------------------------------------------------------
Write-Host "`nTarget Repository: $RepoUrl" -ForegroundColor Gray
$userUrl = Read-Host "Press ENTER to use this URL, or paste a different repository URL"

if (-not [string]::IsNullOrWhiteSpace($userUrl)) {
    $RepoUrl = $userUrl.Trim()
}

# ----------------------------------------------------------------------
# 3. Initialize local repository if required
# ----------------------------------------------------------------------
if (-not (Test-Path ".git")) {
    Write-Host "`nInitializing Git repository..." -ForegroundColor Yellow
    git init
}

# Ensure main branch
git branch -M main

# ----------------------------------------------------------------------
# 4. Stage files
# ----------------------------------------------------------------------
Write-Host "`nStaging repository files..." -ForegroundColor Yellow
git add .

Write-Host "`nGit status:" -ForegroundColor Cyan
git status --short

# ----------------------------------------------------------------------
# 5. Commit
# ----------------------------------------------------------------------
Write-Host "`nCreating commit..." -ForegroundColor Yellow

# Determine whether there is anything to commit.
$stagedChanges = git diff --cached --name-only

if ([string]::IsNullOrWhiteSpace(($stagedChanges -join ""))) {
    Write-Host "No staged changes detected. Skipping commit." -ForegroundColor Gray
}
else {
    git commit -m $CommitMessage
}

# ----------------------------------------------------------------------
# 6. Configure origin safely
# ----------------------------------------------------------------------
Write-Host "`nConfiguring GitHub remote..." -ForegroundColor Yellow

$remotes = @(git remote)

if ($remotes -contains "origin") {
    $currentUrl = (git remote get-url origin).Trim()

    if ($currentUrl -ne $RepoUrl) {
        Write-Host "Updating origin:" -ForegroundColor Gray
        Write-Host "  Old: $currentUrl" -ForegroundColor DarkGray
        Write-Host "  New: $RepoUrl" -ForegroundColor DarkGray
        git remote set-url origin $RepoUrl
    }
    else {
        Write-Host "origin already points to the requested repository." -ForegroundColor Gray
    }
}
else {
    Write-Host "origin does not exist. Adding it now..." -ForegroundColor Gray
    git remote add origin $RepoUrl
}

Write-Host "`nRemote configuration:" -ForegroundColor Cyan
git remote -v

# ----------------------------------------------------------------------
# 7. Push
# ----------------------------------------------------------------------
Write-Host "`nPushing main branch..." -ForegroundColor Yellow

if ($Force) {
    Write-Warning "Force mode enabled. Using --force-with-lease."
    git push -u origin main --force-with-lease
}
else {
    git push -u origin main
}

if ($LASTEXITCODE -ne 0) {
    throw "Git push failed with exit code $LASTEXITCODE."
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " Pipeline successfully deployed!" -ForegroundColor Green
Write-Host " Repository URL: $RepoUrl" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
