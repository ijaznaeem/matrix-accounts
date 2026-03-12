<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            // Drop the global unique constraint on sku
            $table->dropUnique(['sku']);
            // Add a per-company unique constraint (company_id + sku)
            $table->unique(['company_id', 'sku']);
        });
    }

    public function down(): void
    {
        Schema::table('products', function (Blueprint $table) {
            $table->dropUnique(['products_company_id_sku_unique']);
            $table->unique(['sku']);
        });
    }
};
