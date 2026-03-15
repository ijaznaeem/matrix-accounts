param(
    [Parameter(Mandatory = $true)]
    [int]$CompanyId,

    [Parameter(Mandatory = $true)]
    [int]$UserId,

    [Parameter(Mandatory = $true)]
    [string]$UserEmail,

    [int]$Take = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "RBAC remote sync verification" -ForegroundColor Cyan
Write-Host "CompanyId: $CompanyId | UserId: $UserId | UserEmail: $UserEmail | Take: $Take"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$laravelPath = Join-Path $scriptRoot "laravel_sync"
Push-Location $laravelPath
try {
    Write-Host "`n1) Recent sync_changes for users/company_users" -ForegroundColor Yellow
    php artisan tinker --execute="\App\Models\SyncChange::whereIn('table_name',['users','company_users'])->latest()->take($Take)->get(['id','company_id','table_name','record_id','operation','version','created_at'])->toArray();"

    Write-Host "`n2) Remote users row for email" -ForegroundColor Yellow
    php artisan tinker --execute="\App\Models\User::where('email','$UserEmail')->first(['id','email','full_name','is_active']);"

    Write-Host "`n3) Remote company_user mapping" -ForegroundColor Yellow
    php artisan tinker --execute="\App\Models\CompanyUser::where('company_id',$CompanyId)->where('user_id',$UserId)->first(['id','company_id','user_id','role','is_active']);"

    Write-Host "`nDone." -ForegroundColor Green
}
finally {
    Pop-Location
}
