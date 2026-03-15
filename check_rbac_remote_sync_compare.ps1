param(
    [Parameter(Mandatory = $true)]
    [int]$CompanyId,

    [Parameter(Mandatory = $true)]
    [int]$UserId,

    [Parameter(Mandatory = $true)]
    [string]$UserEmail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$laravelPath = Join-Path $scriptRoot "laravel_sync"
Push-Location $laravelPath
try {
    $userJson = php artisan tinker --execute "echo json_encode(\App\Models\User::where('id',$UserId)->orWhere('email','$UserEmail')->first(['id','email','full_name','is_active']));"
    $mappingJson = php artisan tinker --execute "echo json_encode(\App\Models\CompanyUser::where('company_id',$CompanyId)->where('user_id',$UserId)->first(['id','company_id','user_id','role','is_active']));"

    $latestUserChangeJson = php artisan tinker --execute "echo json_encode(\App\Models\SyncChange::where('company_id',$CompanyId)->where('table_name','users')->where('record_id',$UserId)->latest()->first(['id','table_name','record_id','operation','version','data','created_at']));"

    $mappingIdJson = php artisan tinker --execute "echo json_encode(optional(\App\Models\CompanyUser::where('company_id',$CompanyId)->where('user_id',$UserId)->first())->id);"
    $mappingId = [int]($mappingIdJson | Out-String).Trim('"',"`r","`n")

    $latestMappingChangeJson = $null
    if ($mappingId -gt 0) {
        $latestMappingChangeJson = php artisan tinker --execute "echo json_encode(\App\Models\SyncChange::where('company_id',$CompanyId)->where('table_name','company_users')->where('record_id',$mappingId)->latest()->first(['id','table_name','record_id','operation','version','data','created_at']));"
    }

    $user = if (($userJson | Out-String).Trim() -and ($userJson | Out-String).Trim() -ne 'null') { ($userJson | ConvertFrom-Json) } else { $null }
    $mapping = if (($mappingJson | Out-String).Trim() -and ($mappingJson | Out-String).Trim() -ne 'null') { ($mappingJson | ConvertFrom-Json) } else { $null }
    $latestUserChange = if (($latestUserChangeJson | Out-String).Trim() -and ($latestUserChangeJson | Out-String).Trim() -ne 'null') { ($latestUserChangeJson | ConvertFrom-Json) } else { $null }
    $latestMappingChange = if ($latestMappingChangeJson -and ($latestMappingChangeJson | Out-String).Trim() -and ($latestMappingChangeJson | Out-String).Trim() -ne 'null') { ($latestMappingChangeJson | ConvertFrom-Json) } else { $null }

    Write-Host "RBAC Remote Compare" -ForegroundColor Cyan
    Write-Host "CompanyId=$CompanyId UserId=$UserId Email=$UserEmail`n"

    Write-Host "[Remote users row]" -ForegroundColor Yellow
    if ($null -eq $user) {
        Write-Host "No remote user found."
    } else {
        $user | Format-List
    }

    Write-Host "[Remote company_user row]" -ForegroundColor Yellow
    if ($null -eq $mapping) {
        Write-Host "No remote company_user mapping found."
    } else {
        $mapping | Format-List
    }

    Write-Host "[Latest sync_changes for users]" -ForegroundColor Yellow
    if ($null -eq $latestUserChange) {
        Write-Host "No users sync change found."
    } else {
        $latestUserChange | Format-List
    }

    Write-Host "[Latest sync_changes for company_users]" -ForegroundColor Yellow
    if ($null -eq $latestMappingChange) {
        Write-Host "No company_users sync change found."
    } else {
        $latestMappingChange | Format-List
    }

    if ($null -ne $user -and $null -ne $latestUserChange) {
        $userData = $latestUserChange.data | ConvertFrom-Json
        Write-Host "[users compare summary]" -ForegroundColor Green
        [PSCustomObject]@{
            RemoteUserId = $user.id
            RemoteEmail = $user.email
            RemoteFullName = $user.full_name
            RemoteIsActive = $user.is_active
            SyncUserId = $userData.id
            SyncEmail = $userData.email
            SyncFullName = $userData.full_name
            SyncIsActive = $userData.is_active
            Match = (($user.email -eq $userData.email) -and ($user.full_name -eq $userData.full_name) -and ([bool]$user.is_active -eq [bool]$userData.is_active))
        } | Format-Table -AutoSize
    }

    if ($null -ne $mapping -and $null -ne $latestMappingChange) {
        $mapData = $latestMappingChange.data | ConvertFrom-Json
        Write-Host "[company_users compare summary]" -ForegroundColor Green
        [PSCustomObject]@{
            RemoteMapId = $mapping.id
            RemoteCompanyId = $mapping.company_id
            RemoteUserId = $mapping.user_id
            RemoteRole = $mapping.role
            RemoteIsActive = $mapping.is_active
            SyncMapId = $mapData.id
            SyncCompanyId = $mapData.company_id
            SyncUserId = $mapData.user_id
            SyncRole = $mapData.role
            SyncIsActive = $mapData.is_active
            Match = (($mapping.role -eq $mapData.role) -and ([bool]$mapping.is_active -eq [bool]$mapData.is_active))
        } | Format-Table -AutoSize
    }
}
finally {
    Pop-Location
}
