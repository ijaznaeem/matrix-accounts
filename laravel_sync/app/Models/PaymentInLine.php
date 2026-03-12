<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class PaymentInLine extends Model
{
    use HasFactory;

    protected $fillable = [
        'payment_in_id',
        'payment_account_id',
        'amount',
        'reference_no',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
    ];

    public function paymentIn()
    {
        return $this->belongsTo(PaymentIn::class);
    }

    public function paymentAccount()
    {
        return $this->belongsTo(PaymentAccount::class);
    }

    protected static function boot()
    {
        parent::boot();

        static::created(function ($line) {
            $parent = PaymentIn::find($line->payment_in_id);
            if (!$parent) return;
            app(\App\Services\SyncService::class)->recordChange(
                $parent->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'payment_in_lines', $line->id, 'INSERT', $line->toArray()
            );
        });

        static::deleted(function ($line) {
            $parent = PaymentIn::find($line->payment_in_id);
            if (!$parent) return;
            app(\App\Services\SyncService::class)->recordChange(
                $parent->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'payment_in_lines', $line->id, 'DELETE', ['id' => $line->id]
            );
        });
    }
}
