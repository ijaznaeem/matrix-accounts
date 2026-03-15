param(
    [string]$SshPasswordStore = "$HOME/.veyo/ssh_password.xml"
)

$ErrorActionPreference = "Stop"

$storeDir = Split-Path -Parent $SshPasswordStore
if (-not [string]::IsNullOrWhiteSpace($storeDir) -and -not (Test-Path $storeDir)) {
    New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
}

$securePassword = Read-Host "Enter SSH password to store (encrypted for current Windows user)" -AsSecureString
$securePassword | Export-Clixml -Path $SshPasswordStore

Write-Host "Stored SSH password at: $SshPasswordStore" -ForegroundColor Green
Write-Host "Use it with deploy script:" -ForegroundColor Cyan
Write-Host "  .\deploy_changed_laravel.ps1 -UseStoredSshPassword -SshPasswordStore \"$SshPasswordStore\""
