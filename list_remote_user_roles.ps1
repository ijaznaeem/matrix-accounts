param(
    [string]$RemoteRoot = "/home/u383905564/domains/octavions.com/public_html/veyo",
    [string]$RemoteHost = "217.196.55.7",
    [int]$Port = 65002,
    [string]$User = "u383905564",
    [string]$PhpBin = "/opt/alt/php82/usr/bin/php",
    [int]$Take = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tinkerExpr = "echo json_encode(\\App\\Models\\User::query()->select(['id','email','role','is_active'])->orderBy('id')->limit($Take)->get()->toArray());"
$remoteCmd = "cd '$RemoteRoot' && $PhpBin artisan tinker --execute=`"$tinkerExpr`""

Write-Host "Fetching remote users with global roles..." -ForegroundColor Cyan
& ssh -p $Port "$User@$RemoteHost" $remoteCmd
if ($LASTEXITCODE -ne 0) {
    throw "Remote role listing failed with exit code $LASTEXITCODE"
}
