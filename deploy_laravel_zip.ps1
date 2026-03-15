param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$LocalBase = "laravel_sync",
    [string]$RemoteRoot = "/home/u383905564/domains/octavions.com/public_html/veyo",
    [string]$RemoteHost = "217.196.55.7",
    [int]$Port = 65002,
    [string]$User = "u383905564",
    [string]$PhpBin = "/opt/alt/php82/usr/bin/php",
    [string]$HealthUrl = "https://veyo.octavions.com/api/health",
    [switch]$RunOptimizeClear,
    [switch]$RunMigrations,
    [switch]$BuildCache,
    [switch]$RunSeeders,
    [switch]$RunHealthCheck,
    [switch]$RunAllTasks,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-LastExitCode {
    param([string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE"
    }
}

function Get-ChangedLaravelFiles {
    param([string]$Repo, [string]$BaseFolder)

    $changed = @()
    $changed += git -C $Repo diff --name-only -- $BaseFolder
    $changed += git -C $Repo diff --cached --name-only -- $BaseFolder
    $changed += git -C $Repo ls-files --others --exclude-standard -- $BaseFolder

    return $changed |
        Where-Object { $_ -and $_.Trim().Length -gt 0 } |
        Sort-Object -Unique
}

function New-LaravelBundleZip {
    param(
        [string]$Repo,
        [string]$BaseFolder,
        [string[]]$ChangedFiles
    )

    $stagingDir = Join-Path $Repo '.tmp_laravel_zip_stage'
    if (Test-Path $stagingDir) {
        Remove-Item -Path $stagingDir -Recurse -Force
    }
    New-Item -Path $stagingDir -ItemType Directory | Out-Null

    foreach ($relPath in $ChangedFiles) {
        $src = Join-Path $Repo $relPath
        if (-not (Test-Path $src -PathType Leaf)) {
            continue
        }

        $innerPath = $relPath.Substring($BaseFolder.Length).TrimStart('/', '\')
        if ([string]::IsNullOrWhiteSpace($innerPath)) {
            continue
        }

        $dest = Join-Path $stagingDir $innerPath
        $destDir = Split-Path -Path $dest -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $src -Destination $dest -Force
    }

    $zipPath = Join-Path $Repo ("laravel_sync_bundle_{0}.zip" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $zipPath -Force
    Remove-Item -Path $stagingDir -Recurse -Force

    return $zipPath
}

function Upload-And-ExtractBundle {
    param(
        [string]$ZipPath,
        [string]$RemoteServer,
        [int]$SshPort,
        [string]$SshUser,
        [string]$RemoteTargetRoot
    )

    $zipName = Split-Path -Path $ZipPath -Leaf
    $remoteZip = "/tmp/$zipName"

    Write-Host "Uploading zip bundle: $zipName" -ForegroundColor Cyan
    scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new -P $SshPort "$ZipPath" "$SshUser@${RemoteServer}:$remoteZip"
    Assert-LastExitCode 'Zip upload'

    Write-Host "Extracting bundle on remote server..." -ForegroundColor Cyan
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -p $SshPort "$SshUser@$RemoteServer" "unzip -o '$remoteZip' -d '$RemoteTargetRoot' && rm -f '$remoteZip'"
    Assert-LastExitCode 'Remote unzip'
}

function Invoke-RemoteTasks {
    param(
        [string]$RemoteServer,
        [int]$SshPort,
        [string]$SshUser,
        [string]$RemoteTargetRoot,
        [string]$PhpPath,
        [bool]$DoOptimizeClear,
        [bool]$DoMigrations,
        [bool]$DoBuildCache,
        [bool]$DoSeeders
    )

    $commands = @("cd '$RemoteTargetRoot'")

    if ($DoOptimizeClear) {
        $commands += "$PhpPath artisan optimize:clear"
    }
    if ($DoMigrations) {
        $commands += "$PhpPath artisan migrate --force"
    }
    if ($DoSeeders) {
        $commands += "$PhpPath artisan db:seed --force"
    }
    if ($DoBuildCache) {
        $commands += "$PhpPath artisan config:cache"
        $commands += "$PhpPath artisan route:cache"
        $commands += "$PhpPath artisan event:cache"
    }

    if ($commands.Count -le 1) {
        Write-Host 'No remote tasks selected. Skipping post-deploy tasks.' -ForegroundColor Yellow
        return
    }

    $script = $commands -join ' && '
    Write-Host 'Running post-deploy tasks...' -ForegroundColor Cyan
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -p $SshPort "$SshUser@$RemoteServer" $script
    Assert-LastExitCode 'Remote post-deploy tasks'
}

function Invoke-ApiHealthCheck {
    param([string]$Url)

    Write-Host "Running health check: $Url" -ForegroundColor Cyan
    $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 20
    $json = $resp.Content | ConvertFrom-Json

    if ($null -eq $json.status -or $json.status -ne 'ok') {
        throw "Unexpected health payload: $($resp.Content)"
    }

    Write-Host "Health status: $($json.status)" -ForegroundColor Green
}

$selectedOptimize = $RunOptimizeClear.IsPresent
$selectedMigrations = $RunMigrations.IsPresent
$selectedBuildCache = $BuildCache.IsPresent
$selectedSeeders = $RunSeeders.IsPresent
$selectedHealth = $RunHealthCheck.IsPresent

if ($RunAllTasks.IsPresent) {
    $selectedOptimize = $true
    $selectedMigrations = $true
    $selectedBuildCache = $true
}

Write-Host "Collecting changed files under '$LocalBase'..." -ForegroundColor Cyan
$changedFiles = Get-ChangedLaravelFiles -Repo $RepoRoot -BaseFolder $LocalBase

if (-not $changedFiles -or $changedFiles.Count -eq 0) {
    Write-Host "No changed files found under '$LocalBase'." -ForegroundColor Yellow
    exit 0
}

Write-Host "Changed backend files: $($changedFiles.Count)" -ForegroundColor Green
$changedFiles | ForEach-Object { Write-Host " - $_" }

$zipPath = New-LaravelBundleZip -Repo $RepoRoot -BaseFolder $LocalBase -ChangedFiles $changedFiles
Write-Host "Created bundle: $zipPath" -ForegroundColor Green

if ($DryRun.IsPresent) {
    Write-Host 'DryRun enabled: skipping upload and remote execution.' -ForegroundColor Yellow
    exit 0
}

Upload-And-ExtractBundle -ZipPath $zipPath -RemoteServer $RemoteHost -SshPort $Port -SshUser $User -RemoteTargetRoot $RemoteRoot
Invoke-RemoteTasks -RemoteServer $RemoteHost -SshPort $Port -SshUser $User -RemoteTargetRoot $RemoteRoot -PhpPath $PhpBin -DoOptimizeClear $selectedOptimize -DoMigrations $selectedMigrations -DoBuildCache $selectedBuildCache -DoSeeders $selectedSeeders

if ($selectedHealth) {
    Invoke-ApiHealthCheck -Url $HealthUrl
}

Write-Host 'Zip deployment completed successfully.' -ForegroundColor Green