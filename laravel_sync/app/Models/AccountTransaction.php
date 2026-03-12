<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class AccountTransaction extends Model
{
    use HasFactory;

    protected $fillable = [
        'company_id',
        'account_id',
        'transaction_type',
        'reference_id',
        'transaction_date',
        'debit',
        'credit',
        'running_balance',
        'description',
        'reference_no',
        'party_id',
    ];

    protected $casts = [
        'transaction_date' => 'date',
        'debit' => 'decimal:2',
        'credit' => 'decimal:2',
        'running_balance' => 'decimal:2',
    ];

    public function company()
    {
        return $this->belongsTo(Company::class);
    }

    public function account()
    {
        return $this->belongsTo(Account::class);
    }

    protected static function boot()
    {
        parent::boot();

        static::created(function ($entry) {
            app(\App\Services\SyncService::class)->recordChange(
                $entry->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'account_transactions', $entry->id, 'INSERT', $entry->toArray()
            );
        });

        static::updated(function ($entry) {
            app(\App\Services\SyncService::class)->recordChange(
                $entry->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'account_transactions', $entry->id, 'UPDATE', $entry->toArray()
            );
        });
    }
}
