param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$LocalBase = "laravel_sync",
    [string]$RemoteRoot = "/home/u383905564/domains/octavions.com/public_html/veyo",
    [string]$RemoteHost = "217.196.55.7",
    [int]$Port = 65002,
    [string]$User = "u383905564",
    [switch]$IncludeUntracked = $true,
    [string]$BaseRef = "",
    [string]$PhpBin = "/opt/alt/php82/usr/bin/php",
    [switch]$RunPostUploadTasks = $true,
    [switch]$RunMigrations,
    [switch]$RunSeeders,
    [switch]$RunOptimize = $true,
    [switch]$RunHealthCheck = $true,
    [string]$HealthUrl = "https://veyo.octavions.com/api/health"
)

$ErrorActionPreference = "Stop"

function Get-ChangedFiles {
    param(
        [string]$Repo,
        [switch]$WithUntracked,
        [string]$Ref
    )

    if ($Ref -and $Ref.Trim().Length -gt 0) {
        # Committed diff mode (e.g. origin/main)
        $committed = git -C $Repo diff --name-only "$Ref...HEAD"
        return @($committed)
    }

    # Working tree + staged changes
    $unstaged = git -C $Repo diff --name-only
    $staged = git -C $Repo diff --name-only --cached

    $all = @($unstaged) + @($staged)

    if ($WithUntracked) {
        $untracked = git -C $Repo ls-files --others --exclude-standard
        $all += @($untracked)
    }

    return $all
}

function Assert-LastExitCode {
    param(
        [string]$Action
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Collecting changed files..." -ForegroundColor Cyan
$changed = Get-ChangedFiles -Repo $RepoRoot -WithUntracked:$IncludeUntracked -Ref $BaseRef |
    Where-Object { $_ -and $_.Trim().Length -gt 0 } |
    Sort-Object -Unique |
    Where-Object { $_.StartsWith("$LocalBase/") -or $_ -eq $LocalBase }

if (-not $changed -or $changed.Count -eq 0) {
    Write-Host "No changed files found under '$LocalBase'." -ForegroundColor Yellow
    exit 0
}

$uploadList = @()

foreach ($relPath in $changed) {
    $localPath = Join-Path $RepoRoot $relPath

    # Skip deleted paths
    if (-not (Test-Path $localPath -PathType Leaf)) {
        continue
    }

    $relativeFromBase = if ($relPath -eq $LocalBase) {
        ""
    } else {
        $relPath.Substring($LocalBase.Length).TrimStart('/', '\')
    }

    if ([string]::IsNullOrWhiteSpace($relativeFromBase)) {
        continue
    }

    $remotePath = "$RemoteRoot/$($relativeFromBase -replace '\\','/')"
    $remoteDir = Split-Path $remotePath -Parent

    Write-Host "Uploading: $relPath" -ForegroundColor Green

    & ssh -p $Port "$User@$RemoteHost" "mkdir -p '$remoteDir'"
    Assert-LastExitCode -Action "Remote directory creation"

    & scp -P $Port "$localPath" "$User@${RemoteHost}:$remotePath"
    Assert-LastExitCode -Action "File upload ($relPath)"

    $uploadList += $relPath
}

if ($uploadList.Count -eq 0) {
    Write-Host "No uploadable files (only deletions or directories detected)." -ForegroundColor Yellow
    exit 0
}

Write-Host "`nUploaded $($uploadList.Count) file(s) to $User@${RemoteHost}:$RemoteRoot" -ForegroundColor Cyan
$uploadList | ForEach-Object { Write-Host " - $_" }

if ($RunPostUploadTasks) {
    Write-Host "`nRunning post-upload Laravel tasks..." -ForegroundColor Cyan

    $remoteCommands = @(
        "cd '$RemoteRoot'",
        "$PhpBin artisan optimize:clear"
    )

    if ($RunMigrations) {
        $remoteCommands += "$PhpBin artisan migrate --force"
    }

    if ($RunSeeders) {
        $remoteCommands += "$PhpBin artisan db:seed --force"
    }

    if ($RunOptimize) {
        # Avoid `artisan optimize` because some deployments intentionally
        # don't have resources/views and that causes a hard failure.
        $remoteCommands += "$PhpBin artisan config:cache"
        $remoteCommands += "$PhpBin artisan route:cache"
        $remoteCommands += "$PhpBin artisan event:cache"
    }

    $remoteScript = ($remoteCommands -join " && ")
    & ssh -p $Port "$User@$RemoteHost" $remoteScript
    Assert-LastExitCode -Action "Post-upload Laravel tasks"

    Write-Host "Post-upload tasks completed." -ForegroundColor Green
} else {
    Write-Host "`nPost-upload tasks skipped by configuration." -ForegroundColor Yellow
    Write-Host "Suggested remote command:" -ForegroundColor DarkCyan
    Write-Host "ssh -p $Port $User@$RemoteHost `"cd '$RemoteRoot' && $PhpBin artisan optimize:clear`""
}

if ($RunHealthCheck) {
    Write-Host "`nRunning API health check: $HealthUrl" -ForegroundColor Cyan
    try {
        $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 20
        $json = $response.Content | ConvertFrom-Json

        if ($null -eq $json.status -or $json.status -ne 'ok') {
            Write-Error "Health check returned unexpected payload: $($response.Content)"
            exit 1
        }

        Write-Host "Health check passed: status=$($json.status) service=$($json.service)" -ForegroundColor Green
    }
    catch {
        Write-Error "Health check failed: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Host "Health check skipped by configuration." -ForegroundColor Yellow
}
