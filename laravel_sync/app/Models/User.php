<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\HasMany;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable, SoftDeletes;

    protected $fillable = [
        'email',
        'full_name',
        'role',
        'subscriber_id',
        'max_companies',
        'subscription_expires_at',
        'password',
        'is_active',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected $casts = [
        'role' => 'string',
        'subscriber_id' => 'integer',
        'max_companies' => 'integer',
        'subscription_expires_at' => 'datetime',
        'is_active' => 'boolean',
        'email_verified_at' => 'datetime',
        'password' => 'hashed',
    ];

    public function subscriber()
    {
        return $this->belongsTo(User::class, 'subscriber_id');
    }

    public function tenantUsers()
    {
        return $this->hasMany(User::class, 'subscriber_id');
    }

    public function clientBillingRecords(): HasMany
    {
        return $this->hasMany(ClientBillingRecord::class, 'client_admin_id');
    }

    public function createdBillingRecords(): HasMany
    {
        return $this->hasMany(ClientBillingRecord::class, 'created_by_user_id');
    }

    public function companies()
    {
        return $this->belongsToMany(Company::class, 'company_user')
            ->withPivot('role', 'user_group_id', 'is_active')
            ->withTimestamps();
    }

    public function syncChanges()
    {
        return $this->hasMany(SyncChange::class);
    }
}
