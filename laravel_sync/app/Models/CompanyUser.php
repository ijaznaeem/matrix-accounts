<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CompanyUser extends Model
{
    protected $table = 'company_user';

    protected $fillable = [
        'company_id',
        'user_id',
        'role',
        'user_group_id',
        'is_active',
    ];

    protected $casts = [
        'company_id' => 'integer',
        'user_id' => 'integer',
        'user_group_id' => 'integer',
        'is_active' => 'boolean',
    ];
}
