<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Transaction extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = [
        'company_id',
        'type',
        'date',
        'reference_no',
        'party_id',
        'cash_bank_account',
        'total_amount',
        'is_posted',
        'created_by_user_id',
    ];

    protected $casts = [
        'date' => 'date',
        'total_amount' => 'decimal:2',
        'is_posted' => 'boolean',
    ];

    public function company()
    {
        return $this->belongsTo(Company::class);
    }

    public function lines()
    {
        return $this->hasMany(TransactionLine::class);
    }

    public function invoice()
    {
        return $this->hasOne(Invoice::class);
    }

    protected static function boot()
    {
        parent::boot();

        static::created(function ($txn) {
            app(\App\Services\SyncService::class)->recordChange(
                $txn->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'transactions', $txn->id, 'INSERT', $txn->toArray()
            );
        });

        static::updated(function ($txn) {
            app(\App\Services\SyncService::class)->recordChange(
                $txn->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'transactions', $txn->id, 'UPDATE', $txn->toArray()
            );
        });

        static::deleted(function ($txn) {
            app(\App\Services\SyncService::class)->recordChange(
                $txn->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'transactions', $txn->id, 'DELETE', ['id' => $txn->id]
            );
        });
    }
}
