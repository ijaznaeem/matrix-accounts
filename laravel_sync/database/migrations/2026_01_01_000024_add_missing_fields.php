<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Add columns that exist in the Flutter Isar models but were missing
 * from the original migrations:
 *  - invoices: previous_balance, paid_amount, remaining_balance, invoice_number
 *  - account_transactions: party_id index
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('invoices', function (Blueprint $table) {
            $table->decimal('previous_balance', 15, 2)->default(0)->after('grand_total');
            $table->decimal('paid_amount', 15, 2)->default(0)->after('previous_balance');
            $table->decimal('remaining_balance', 15, 2)->default(0)->after('paid_amount');
            $table->string('invoice_number')->nullable()->after('remaining_balance');

            $table->index('invoice_number');
        });

        Schema::table('account_transactions', function (Blueprint $table) {
            $table->index('party_id');
        });
    }

    public function down(): void
    {
        Schema::table('invoices', function (Blueprint $table) {
            $table->dropIndex(['invoice_number']);
            $table->dropColumn(['previous_balance', 'paid_amount', 'remaining_balance', 'invoice_number']);
        });

        Schema::table('account_transactions', function (Blueprint $table) {
            $table->dropIndex(['party_id']);
        });
    }
};
