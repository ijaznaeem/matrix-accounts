<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use App\Models\User;

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

Artisan::command('octavision:create-super-admin {email} {password} {name=Octavision Super Admin}', function () {
    $email = strtolower(trim((string) $this->argument('email')));
    $password = (string) $this->argument('password');
    $name = trim((string) $this->argument('name'));

    if ($email === '' || $password === '') {
        $this->error('Email and password are required.');
        return;
    }

    $existing = User::where('email', $email)->first();
    if ($existing) {
        $existing->full_name = $name !== '' ? $name : $existing->full_name;
        $existing->role = 'super_admin';
        $existing->subscriber_id = null;
        $existing->max_companies = 0;
        $existing->subscription_expires_at = null;
        $existing->is_active = true;
        $existing->password = Hash::make($password);
        $existing->save();

        $this->info('Existing user upgraded to super_admin successfully.');
        return;
    }

    User::create([
        'email' => $email,
        'full_name' => $name !== '' ? $name : 'Octavision Super Admin',
        'role' => 'super_admin',
        'subscriber_id' => null,
        'max_companies' => 0,
        'subscription_expires_at' => null,
        'password' => Hash::make($password),
        'is_active' => true,
    ]);

    $this->info('Super admin created successfully.');
})->purpose('Create or promote a Laravel super admin for the Octavision control panel');
