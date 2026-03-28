<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ClientBillingRecord extends Model
{
    use HasFactory;

    protected $fillable = [
        'client_admin_id',
        'created_by_user_id',
        'amount',
        'payment_method',
        'paid_on',
        'notes',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'paid_on' => 'date',
        'client_admin_id' => 'integer',
        'created_by_user_id' => 'integer',
    ];

    public function clientAdmin()
    {
        return $this->belongsTo(User::class, 'client_admin_id');
    }

    public function createdBy()
    {
        return $this->belongsTo(User::class, 'created_by_user_id');
    }
}
