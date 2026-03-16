<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private string $indexName = 'invoices_company_invoice_number_unique';

    public function up(): void
    {
        if (!Schema::hasTable('invoices')) {
            return;
        }

        // Normalize existing duplicates per company to avoid migration failure.
        $rows = DB::table('invoices')
            ->whereNotNull('invoice_number')
            ->where('invoice_number', '!=', '')
            ->orderBy('company_id')
            ->orderBy('invoice_number')
            ->orderBy('id')
            ->get(['id', 'company_id', 'invoice_number']);

        $seen = [];

        foreach ($rows as $row) {
            $companyId = (int) $row->company_id;
            $current = trim((string) $row->invoice_number);
            if ($current === '') {
                continue;
            }

            $companySeen = $seen[$companyId] ?? [];
            $key = mb_strtolower($current);

            if (!isset($companySeen[$key])) {
                $companySeen[$key] = true;
                $seen[$companyId] = $companySeen;
                continue;
            }

            $suffix = 2;
            do {
                $candidate = $current . '-' . $suffix;
                $candidateKey = mb_strtolower($candidate);
                $suffix++;
            } while (isset($companySeen[$candidateKey]));

            DB::table('invoices')
                ->where('id', $row->id)
                ->update(['invoice_number' => $candidate]);

            $companySeen[$candidateKey] = true;
            $seen[$companyId] = $companySeen;
        }

        Schema::table('invoices', function (Blueprint $table) {
            $table->unique(['company_id', 'invoice_number'], $this->indexName);
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('invoices')) {
            return;
        }

        Schema::table('invoices', function (Blueprint $table) {
            $table->dropUnique($this->indexName);
        });
    }
};
