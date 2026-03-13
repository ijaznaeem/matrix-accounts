<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote')->hourly();

Artisan::command('sync:dedupe-changes {--company_id=} {--dry-run}', function () {
    $companyId = $this->option('company_id');
    $dryRun = (bool) $this->option('dry-run');

    $query = DB::table('sync_changes as newer')
        ->join('sync_changes as older', function ($join) {
            $join->on('newer.company_id', '=', 'older.company_id')
                ->on('newer.table_name', '=', 'older.table_name')
                ->on('newer.record_id', '=', 'older.record_id')
                ->on('newer.operation', '=', 'older.operation')
                ->on('newer.device_id', '=', 'older.device_id')
                ->on('newer.created_at', '=', 'older.created_at')
                ->whereColumn('newer.id', '>', 'older.id')
                ->whereRaw('CAST(newer.data AS CHAR) = CAST(older.data AS CHAR)');
        });

    if (!empty($companyId)) {
        $query->where('newer.company_id', (int) $companyId);
    }

    $duplicateIds = $query
        ->distinct()
        ->pluck('newer.id')
        ->map(static fn ($id) => (int) $id)
        ->values();

    $count = $duplicateIds->count();

    if ($count === 0) {
        $this->info('No exact duplicate sync_changes rows found.');
        return;
    }

    $this->warn("Found {$count} duplicate sync_changes rows.");

    if ($dryRun) {
        $this->line('Dry run mode: nothing deleted.');
        return;
    }

    DB::table('sync_changes')
        ->whereIn('id', $duplicateIds->all())
        ->delete();

    $this->info("Deleted {$count} duplicate sync_changes rows.");
})->purpose('Remove exact duplicate rows from sync_changes safely');
