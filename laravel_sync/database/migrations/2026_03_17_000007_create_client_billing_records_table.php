<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('client_billing_records', function (Blueprint $table) {
            $table->id();
            $table->foreignId('client_admin_id')->constrained('users')->cascadeOnDelete();
            $table->foreignId('created_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->decimal('amount', 14, 2);
            $table->string('payment_method', 50);
            $table->date('paid_on');
            $table->text('notes')->nullable();
            $table->timestamps();

            $table->index(['client_admin_id', 'paid_on']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('client_billing_records');
    }
};
