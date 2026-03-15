<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('users', 'role')) {
            Schema::table('users', function (Blueprint $table) {
                $table->string('role')->default('user')->after('full_name');
                $table->index('role');
            });
        }

        DB::table('users')
            ->whereExists(function ($query) {
                $query->selectRaw('1')
                    ->from('company_user')
                    ->whereColumn('company_user.user_id', 'users.id')
                    ->where('company_user.role', 'admin')
                    ->where('company_user.is_active', true);
            })
            ->update(['role' => 'admin']);
    }

    public function down(): void
    {
        if (Schema::hasColumn('users', 'role')) {
            Schema::table('users', function (Blueprint $table) {
                $table->dropIndex(['role']);
                $table->dropColumn('role');
            });
        }
    }
};
