<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sync_changes', function (Blueprint $table) {
            $table->string('op_uuid', 100)->nullable()->after('device_id');
            $table->index(['company_id', 'op_uuid']);
        });
    }

    public function down(): void
    {
        Schema::table('sync_changes', function (Blueprint $table) {
            $table->dropIndex(['company_id', 'op_uuid']);
            $table->dropColumn('op_uuid');
        });
    }
};
