<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class PaymentOutLine extends Model
{
    use HasFactory;

    protected $fillable = [
        'payment_out_id',
        'payment_account_id',
        'amount',
        'reference_no',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
    ];

    public function paymentOut()
    {
        return $this->belongsTo(PaymentOut::class);
    }

    public function paymentAccount()
    {
        return $this->belongsTo(PaymentAccount::class);
    }

    protected static function boot()
    {
        parent::boot();

        static::created(function ($line) {
            $parent = PaymentOut::find($line->payment_out_id);
            if (!$parent) return;
            app(\App\Services\SyncService::class)->recordChange(
                $parent->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'payment_out_lines', $line->id, 'INSERT', $line->toArray()
            );
        });

        static::deleted(function ($line) {
            $parent = PaymentOut::find($line->payment_out_id);
            if (!$parent) return;
            app(\App\Services\SyncService::class)->recordChange(
                $parent->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'payment_out_lines', $line->id, 'DELETE', ['id' => $line->id]
            );
        });
    }
}
