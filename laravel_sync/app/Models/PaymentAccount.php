<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class PaymentAccount extends Model
{
    use HasFactory;

    protected $fillable = [
        'company_id',
        'account_type',
        'account_name',
        'bank_name',
        'account_number',
        'ifsc_code',
        'icon',
        'is_active',
        'is_default',
    ];

    protected $casts = [
        'is_active' => 'boolean',
        'is_default' => 'boolean',
    ];

    public function company()
    {
        return $this->belongsTo(Company::class);
    }

    protected static function boot()
    {
        parent::boot();

        static::created(function ($a) {
            app(\App\Services\SyncService::class)->recordChange(
                $a->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'payment_accounts', $a->id, 'INSERT', $a->toArray()
            );
        });

        static::updated(function ($a) {
            app(\App\Services\SyncService::class)->recordChange(
                $a->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'payment_accounts', $a->id, 'UPDATE', $a->toArray()
            );
        });
    }
}
