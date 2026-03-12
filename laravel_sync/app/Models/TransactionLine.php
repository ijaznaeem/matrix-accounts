<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class TransactionLine extends Model
{
    use HasFactory;

    protected $fillable = [
        'transaction_id',
        'product_id',
        'expense_category_id',
        'party_id',
        'description',
        'quantity',
        'unit_price',
        'line_amount',
    ];

    protected $casts = [
        'quantity' => 'decimal:3',
        'unit_price' => 'decimal:2',
        'line_amount' => 'decimal:2',
    ];

    public function transaction()
    {
        return $this->belongsTo(Transaction::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }

    protected static function boot()
    {
        parent::boot();

        static::created(function ($line) {
            $txn = Transaction::find($line->transaction_id);
            if (!$txn) return;
            app(\App\Services\SyncService::class)->recordChange(
                $txn->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'transaction_lines', $line->id, 'INSERT', $line->toArray()
            );
        });

        static::updated(function ($line) {
            $txn = Transaction::find($line->transaction_id);
            if (!$txn) return;
            app(\App\Services\SyncService::class)->recordChange(
                $txn->company_id, auth()->id(),
                request()->header('X-Device-Id'),
                'transaction_lines', $line->id, 'UPDATE', $line->toArray()
            );
        });
    }
}
