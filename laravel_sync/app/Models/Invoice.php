<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Auth;

class Invoice extends Model
{
    use HasFactory, SoftDeletes;

    protected $fillable = [
        'company_id',
        'transaction_id',
        'invoice_type',
        'party_id',
        'invoice_date',
        'due_date',
        'grand_total',
        'status',
        'previous_balance',
        'paid_amount',
        'remaining_balance',
        'invoice_number',
        'notes',
        'attachment_path',
    ];

    protected $casts = [
        'invoice_date'      => 'date',
        'due_date'          => 'date',
        'grand_total'       => 'decimal:2',
        'previous_balance'  => 'decimal:2',
        'paid_amount'       => 'decimal:2',
        'remaining_balance' => 'decimal:2',
    ];

    public function company()
    {
        return $this->belongsTo(Company::class);
    }

    protected static function boot()
    {
        parent::boot();

        static::created(function ($invoice) {
            app(\App\Services\SyncService::class)->recordChange(
                $invoice->company_id,
                Auth::id(),
                request()->header('X-Device-Id'),
                'invoices',
                $invoice->id,
                'INSERT',
                $invoice->toArray()
            );
        });

        static::updated(function ($invoice) {
            app(\App\Services\SyncService::class)->recordChange(
                $invoice->company_id,
                Auth::id(),
                request()->header('X-Device-Id'),
                'invoices',
                $invoice->id,
                'UPDATE',
                $invoice->toArray()
            );
        });

        static::deleted(function ($invoice) {
            app(\App\Services\SyncService::class)->recordChange(
                $invoice->company_id,
                Auth::id(),
                request()->header('X-Device-Id'),
                'invoices',
                $invoice->id,
                'DELETE',
                ['id' => $invoice->id]
            );
        });
    }

    public function transaction()
    {
        return $this->belongsTo(Transaction::class);
    }

    public function party()
    {
        return $this->belongsTo(Party::class);
    }
}
