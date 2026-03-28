<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('users', 'subscription_expires_at')) {
            Schema::table('users', function (Blueprint $table) {
                $table->timestamp('subscription_expires_at')->nullable()->after('max_companies');
                $table->index('subscription_expires_at');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('users', 'subscription_expires_at')) {
            Schema::table('users', function (Blueprint $table) {
                $table->dropIndex(['subscription_expires_at']);
                $table->dropColumn('subscription_expires_at');
            });
        }
    }
};
