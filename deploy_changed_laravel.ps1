param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$LocalBase = "laravel_sync",
    [string]$RemoteRoot = "/home/u383905564/domains/octavions.com/public_html/veyo",
    [string]$RemoteHost = "217.196.55.7",
    [int]$Port = 65002,
    [string]$User = "u383905564",
    [string]$PhpBin = "/opt/alt/php82/usr/bin/php",
    [string]$HealthUrl = "https://veyo.octavions.com/api/health",
    [switch]$Interactive,
    [switch]$RunOptimizeClear,
    [switch]$RunMigrations,
    [switch]$RunSeeders,
    [switch]$BuildCache,
    [switch]$RunAllTasks,
    [switch]$RunHealthCheck
)

$ErrorActionPreference = "Stop"

# -----------------------------------------
# Get changed files
# -----------------------------------------

function Get-ChangedFiles {

    param([string]$Repo)

    $unstaged = git -C $Repo diff --name-only
    $staged = git -C $Repo diff --name-only --cached
    $untracked = git -C $Repo ls-files --others --exclude-standard

    $all = @($unstaged) + @($staged) + @($untracked)

    return $all |
        Where-Object { $_ -and $_.Trim().Length -gt 0 } |
        Sort-Object -Unique
}

# -----------------------------------------
# Get deleted files
# -----------------------------------------

function Get-DeletedFiles {

    param([string]$Repo)

    $unstagedDeleted = git -C $Repo diff --name-only --diff-filter=D
    $stagedDeleted = git -C $Repo diff --name-only --cached --diff-filter=D

    return @($unstagedDeleted) + @($stagedDeleted) |
        Where-Object { $_ -and $_.Trim().Length -gt 0 } |
        Sort-Object -Unique
}

function Assert-LastExitCode {

    param([string]$Action)

    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE"
    }
}

# -----------------------------------------
# Remote SSH command
# -----------------------------------------

function Invoke-Remote {

    param([string]$Command)

    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -p $Port "$User@$RemoteHost" $Command
    Assert-LastExitCode "Remote command"
}

# -----------------------------------------
# Upload file
# -----------------------------------------

function Upload-File {

    param(
        [string]$Local,
        [string]$Remote
    )

    scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new -P $Port "$Local" "$User@${RemoteHost}:$Remote"
    Assert-LastExitCode "File upload"
}

function Invoke-HealthCheck {

    Write-Host "Running health check..." -ForegroundColor Cyan

    try {

        $resp = Invoke-WebRequest -Uri $HealthUrl -TimeoutSec 20
        $json = $resp.Content | ConvertFrom-Json

        if ($null -eq $json.status -or $json.status -ne 'ok') {
            throw "Unexpected health payload: $($resp.Content)"
        }

        Write-Host "Health status: $($json.status)" -ForegroundColor Green

    } catch {

        Write-Host "Health check failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Invoke-TaskSelection {

    param([string[]]$SelectedOptions)

    $commands = @("cd '$RemoteRoot'")

    foreach ($option in $SelectedOptions) {
        switch ($option) {
            '1' {
                $commands += "$PhpBin artisan optimize:clear"
            }
            '2' {
                $commands += "$PhpBin artisan migrate --force"
            }
            '3' {
                $commands += "$PhpBin artisan db:seed --force"
            }
            '4' {
                $commands += "$PhpBin artisan config:cache"
                $commands += "$PhpBin artisan route:cache"
                $commands += "$PhpBin artisan event:cache"
            }
            '5' {
                $commands += "$PhpBin artisan optimize:clear"
                $commands += "$PhpBin artisan migrate --force"
                $commands += "$PhpBin artisan db:seed --force"
                $commands += "$PhpBin artisan config:cache"
                $commands += "$PhpBin artisan route:cache"
                $commands += "$PhpBin artisan event:cache"
            }
            '6' {
                Invoke-HealthCheck
            }
            default {
                throw "Unsupported task option: $option"
            }
        }
    }

    if ($commands.Count -gt 1) {
        $script = $commands -join " && "
        Invoke-Remote $script
        Write-Host "Task completed." -ForegroundColor Green
    }
}

# -----------------------------------------
# Collect changed files
# -----------------------------------------

Write-Host "Collecting changed files..." -ForegroundColor Cyan

$changed = Get-ChangedFiles -Repo $RepoRoot |
    Where-Object { $_.StartsWith("$LocalBase/") }

if (-not $changed) {

    Write-Host "No changed files detected." -ForegroundColor Yellow
} else {

    $uploadList = @()

    foreach ($relPath in $changed) {

        $localPath = Join-Path $RepoRoot $relPath

        if (-not (Test-Path $localPath -PathType Leaf)) {
            continue
        }

        $relativeFromBase = $relPath.Substring($LocalBase.Length).TrimStart('/', '\')

        if ([string]::IsNullOrWhiteSpace($relativeFromBase)) {
            continue
        }

        $remotePath = "$RemoteRoot/$($relativeFromBase -replace '\\','/')"
        $remoteDir = Split-Path $remotePath -Parent

        Write-Host "Uploading: $relPath" -ForegroundColor Green

        Invoke-Remote "mkdir -p '$remoteDir'"
        Upload-File $localPath $remotePath

        $uploadList += $relPath
    }

    Write-Host ""
    Write-Host "Uploaded $($uploadList.Count) file(s)" -ForegroundColor Cyan

    $uploadList | ForEach-Object { Write-Host " - $_" }
}

# -----------------------------------------
# Delete removed files from server
# -----------------------------------------

Write-Host ""
Write-Host "Checking deleted files..." -ForegroundColor Cyan

$deleted = Get-DeletedFiles -Repo $RepoRoot |
    Where-Object { $_.StartsWith("$LocalBase/") }

foreach ($file in $deleted) {

    $relative = $file.Substring($LocalBase.Length).TrimStart('/', '\')

    if ([string]::IsNullOrWhiteSpace($relative)) {
        continue
    }

    $remotePath = "$RemoteRoot/$($relative -replace '\\','/')"

    Write-Host "Removing remote file: $file" -ForegroundColor Yellow

    Invoke-Remote "rm -f '$remotePath'"
}

# -----------------------------------------
# Upload summary
# -----------------------------------------

# -----------------------------------------
# Laravel post deployment menu
# -----------------------------------------

function Show-Menu {

    Write-Host ""
    Write-Host "========= Laravel Deployment =========" -ForegroundColor Cyan
    Write-Host "1 Clear optimize cache"
    Write-Host "2 Run migrations"
    Write-Host "3 Run seeders"
    Write-Host "4 Build config/route/event cache"
    Write-Host "5 Run ALL tasks"
    Write-Host "6 Health check"
    Write-Host "0 Exit"

    return Read-Host "Select option"
}

$hasTaskFlags =
    $RunOptimizeClear.IsPresent -or
    $RunMigrations.IsPresent -or
    $RunSeeders.IsPresent -or
    $BuildCache.IsPresent -or
    $RunAllTasks.IsPresent -or
    $RunHealthCheck.IsPresent

if ($hasTaskFlags -and -not $Interactive.IsPresent) {

    $selectedOptions = @()

    if ($RunAllTasks.IsPresent) {
        $selectedOptions += '5'
    } else {
        if ($RunOptimizeClear.IsPresent) {
            $selectedOptions += '1'
        }
        if ($RunMigrations.IsPresent) {
            $selectedOptions += '2'
        }
        if ($RunSeeders.IsPresent) {
            $selectedOptions += '3'
        }
        if ($BuildCache.IsPresent) {
            $selectedOptions += '4'
        }
    }

    if ($RunHealthCheck.IsPresent) {
        $selectedOptions += '6'
    }

    if ($selectedOptions.Count -gt 0) {
        Invoke-TaskSelection -SelectedOptions $selectedOptions
    }

    return
}

while ($true) {

    $choice = Show-Menu

    switch ($choice) {
        "0" { break }
        "1" { Invoke-TaskSelection -SelectedOptions @('1') }
        "2" { Invoke-TaskSelection -SelectedOptions @('2') }
        "3" { Invoke-TaskSelection -SelectedOptions @('3') }
        "4" { Invoke-TaskSelection -SelectedOptions @('4') }
        "5" { Invoke-TaskSelection -SelectedOptions @('5') }
        "6" { Invoke-TaskSelection -SelectedOptions @('6') }
        default {
            Write-Host "Invalid option." -ForegroundColor Red
            continue
        }
    }
}