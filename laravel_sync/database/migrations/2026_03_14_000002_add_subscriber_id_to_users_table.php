<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('users', 'subscriber_id')) {
            Schema::table('users', function (Blueprint $table) {
                $table->unsignedBigInteger('subscriber_id')->nullable()->after('role');
                $table->index('subscriber_id');
            });
        }

        // Existing global admins become their own tenant root.
        DB::table('users')
            ->where('role', 'admin')
            ->whereNull('subscriber_id')
            ->update(['subscriber_id' => DB::raw('id')]);
    }

    public function down(): void
    {
        if (Schema::hasColumn('users', 'subscriber_id')) {
            Schema::table('users', function (Blueprint $table) {
                $table->dropIndex(['subscriber_id']);
                $table->dropColumn('subscriber_id');
            });
        }
    }
};
