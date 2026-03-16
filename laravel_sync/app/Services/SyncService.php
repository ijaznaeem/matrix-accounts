<?php

namespace App\Services;

use App\Models\SyncChange;
use App\Models\SyncVersion;
use App\Models\DeviceSyncStatus;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

class SyncService
{
    /**
     * Record a change in the sync_changes table
     */
    public function recordChange(
        int $companyId,
        ?int $userId,
        ?string $deviceId,
        string $tableName,
        int $recordId,
        string $operation,
        array $data,
        ?string $opUuid = null
    ): SyncChange {
        // Get next version number
        $version = $this->getNextVersion($companyId);

        // Create sync change record
        return SyncChange::create([
            'company_id' => $companyId,
            'user_id' => $userId ?? 1, // Default to system user
            'device_id' => $deviceId ?? 'server',
            'op_uuid' => $opUuid,
            'table_name' => $tableName,
            'record_id' => $recordId,
            'operation' => $operation,
            'data' => $data,
            'version' => $version,
        ]);
    }

    /**
     * Get the next version number for a company
     */
    protected function getNextVersion(int $companyId): int
    {
        return DB::transaction(function () use ($companyId) {
            $syncVersion = SyncVersion::firstOrCreate(
                ['company_id' => $companyId],
                ['current_version' => 0]
            );

            $syncVersion->increment('current_version');
            $syncVersion->refresh();

            return $syncVersion->current_version;
        });
    }

    /**
     * Pull changes from server (device requesting updates)
     */
    public function pullChanges(
        int $companyId,
        string $deviceId,
        int $lastVersion = 0,
        ?array $tables = null
    ): array {
        $backfillDebug = null;

        if ($lastVersion === 0) {
            $backfillDebug = $this->backfillMissingSyncHistory($companyId, $tables);
        }

        $query = SyncChange::where('company_id', $companyId)
            ->where('version', '>', $lastVersion)
            ->orderBy('version', 'asc');

        if ($tables) {
            $query->whereIn('table_name', $tables);
        }

        $changes = $query->get();

        $currentVersion = $this->getCurrentVersion($companyId);

        // Update device sync status
        $this->updateDeviceSyncStatus($companyId, $deviceId, $currentVersion);

        $response = [
            'success' => true,
            'current_version' => $currentVersion,
            'changes' => $changes->map(function ($change) {
                return [
                    'version' => $change->version,
                    'table' => $change->table_name,
                    'record_id' => $change->record_id,
                    'operation' => $change->operation,
                    'data' => $change->data,
                    'timestamp' => $change->created_at->toIso8601String(),
                ];
            })->toArray(),
        ];

        if ($backfillDebug !== null) {
            $response['debug'] = [
                'backfill' => $backfillDebug,
            ];
        }

        return $response;
    }

    /**
     * Ensure existing company data is represented in sync_changes.
     * This enables fresh installs (lastVersion=0) to receive full current state
     * even when legacy rows were inserted before sync logging existed.
     */
    protected function backfillMissingSyncHistory(int $companyId, ?array $tables = null): array
    {
        $summary = [
            'processed_tables' => 0,
            'created_sync_changes' => 0,
            'skipped_tables' => [],
            'skipped_rows' => 0,
            'sample_row_errors' => [],
        ];

        foreach ($this->getSyncableTableNames($tables) as $tableName) {
            $modelClass = $this->getModelClass($tableName);
            if (!$modelClass) {
                $summary['skipped_tables'][] = [
                    'table' => $tableName,
                    'reason' => 'unknown_model',
                ];
                continue;
            }

            try {
                $modelInstance = new $modelClass();
                $physicalTable = $modelInstance->getTable();

                if (!Schema::hasTable($physicalTable)) {
                    Log::warning('Sync backfill skipped missing table', [
                        'company_id' => $companyId,
                        'table_name' => $tableName,
                        'physical_table' => $physicalTable,
                    ]);

                    $summary['skipped_tables'][] = [
                        'table' => $tableName,
                        'reason' => 'missing_table',
                        'physical_table' => $physicalTable,
                    ];
                    continue;
                }

                $summary['processed_tables']++;

                $query = $this->companyScopedQuery($tableName, $modelClass, $companyId);

                foreach ($query->cursor() as $row) {
                    try {
                        $recordId = (int) $row->id;

                        $existsInHistory = SyncChange::where('company_id', $companyId)
                            ->where('table_name', $tableName)
                            ->where('record_id', $recordId)
                            ->exists();

                        if ($existsInHistory) {
                            continue;
                        }

                        $this->recordChange(
                            $companyId,
                            null,
                            'server',
                            $tableName,
                            $recordId,
                            'INSERT',
                            $row->toArray()
                        );

                        $summary['created_sync_changes']++;
                    } catch (\Throwable $rowError) {
                        Log::warning('Sync backfill skipped row', [
                            'company_id' => $companyId,
                            'table_name' => $tableName,
                            'error' => $rowError->getMessage(),
                        ]);

                        $summary['skipped_rows']++;
                        if (count($summary['sample_row_errors']) < 5) {
                            $summary['sample_row_errors'][] = [
                                'table' => $tableName,
                                'error' => $rowError->getMessage(),
                            ];
                        }
                    }
                }
            } catch (\Throwable $tableError) {
                Log::warning('Sync backfill skipped table due to error', [
                    'company_id' => $companyId,
                    'table_name' => $tableName,
                    'error' => $tableError->getMessage(),
                ]);

                $summary['skipped_tables'][] = [
                    'table' => $tableName,
                    'reason' => 'table_error',
                    'error' => $tableError->getMessage(),
                ];
                continue;
            }
        }

        return $summary;
    }

    /**
     * Get syncable table names with optional filtering.
     */
    protected function getSyncableTableNames(?array $tables = null): array
    {
        $all = [
            'parties',
            'products',
            'invoices',
            'transactions',
            'transaction_lines',
            'accounts',
            'account_transactions',
            'payment_accounts',
            'payment_ins',
            'payment_in_lines',
            'payment_outs',
            'payment_out_lines',
            'stock_ledgers',
            'users',
            'company_users',
            'item_categories',
        ];

        if (!$tables || count($tables) === 0) {
            return $all;
        }

        return array_values(array_intersect($all, $tables));
    }

    /**
     * Push changes from device to server
     */
    public function pushChanges(
        int $companyId,
        int $userId,
        string $deviceId,
        array $changes
    ): array {
        $idMappings = [];
        $conflicts = [];

        DB::transaction(function () use ($companyId, $userId, $deviceId, $changes, &$idMappings, &$conflicts) {
            foreach ($changes as $change) {
                try {
                    $opUuid = isset($change['op_uuid'])
                        ? trim((string) $change['op_uuid'])
                        : null;

                    if ($opUuid === '') {
                        $opUuid = null;
                    }

                    if ($opUuid !== null) {
                        $existing = SyncChange::where('company_id', $companyId)
                            ->where('op_uuid', $opUuid)
                            ->first();

                        if ($existing) {
                            if (isset($change['local_id']) && $existing->operation === 'INSERT') {
                                $idMappings[$change['local_id']] = $existing->record_id;
                            }
                            continue;
                        }
                    }

                    $result = $this->applyChange(
                        $companyId,
                        $userId,
                        $deviceId,
                        $change,
                        $opUuid
                    );

                    // Map temporary IDs to server IDs
                    if (isset($change['local_id']) && isset($result['server_id'])) {
                        $idMappings[$change['local_id']] = $result['server_id'];
                    }

                    if (isset($result['conflict'])) {
                        $conflicts[] = $result['conflict'];
                    }
                } catch (\Exception $e) {
                    Log::error('Error applying change: ' . $e->getMessage(), [
                        'change' => $change,
                        'exception' => $e,
                    ]);
                }
            }
        });

        $currentVersion = $this->getCurrentVersion($companyId);

        return [
            'success' => true,
            'current_version' => $currentVersion,
            'conflicts' => $conflicts,
            'id_mappings' => $idMappings,
        ];
    }

    /**
     * Tables whose rows carry company_id directly.
     */
    protected array $directCompanyTables = [
        'parties',
        'products',
        'invoices',
        'transactions',
        'accounts',
        'account_transactions',
        'payment_accounts',
        'payment_ins',
        'payment_outs',
        'stock_ledgers',
        'company_users',
        'item_categories',
    ];

    protected function applyChange(
        int $companyId,
        int $userId,
        string $deviceId,
        array $change,
        ?string $opUuid = null
    ): array {
        $tableName = $change['table'];
        $operation = $change['operation'];
        $data = $change['data'];

        // Get the model class
        $modelClass = $this->getModelClass($tableName);
        if (!$modelClass) {
            throw new \Exception("Unknown table: {$tableName}");
        }

        $result = [];

        // These will be set in each switch branch and used to log to sync_changes.
        $syncRecordId = 0;
        $syncData     = $data;

        switch ($operation) {
            case 'INSERT':
                unset($data['id']);
                if ($this->tableUsesDirectCompanyId($tableName)) {
                    $data['company_id'] = $companyId;
                }

                $record = $modelClass::create($data);
                $result['server_id'] = $record->id;
                $syncRecordId        = (int) $record->id;
                // Include the server-assigned id so pulling devices receive the canonical id.
                $syncData            = $record->toArray();
                break;

            case 'UPDATE':
                $recordId = $data['id'] ?? $change['record_id'];
                $query = $this->companyScopedQuery($tableName, $modelClass, $companyId);
                $record = $query->find($recordId);

                if ($record) {
                    $record->update($data);
                } else {
                    throw new \Exception("Record not found: {$tableName}#{$recordId}");
                }
                $syncRecordId = (int) $recordId;
                // Always publish the full canonical row for UPDATE so pull clients
                // can safely apply changes even if the incoming push payload was partial.
                $syncData     = $record->fresh()->toArray();
                break;

            case 'DELETE':
                $recordId = $data['id'] ?? $change['record_id'];
                $query = $this->companyScopedQuery($tableName, $modelClass, $companyId);
                $record = $query->find($recordId);

                if ($record) {
                    $record->delete();
                }
                $syncRecordId = (int) ($recordId ?? 0);
                $syncData     = ['id' => $syncRecordId];
                break;
        }

        // ── Critical: log every applied change to sync_changes ─────────────
        // Without this entry, other devices querying sync_changes during a pull
        // will never see the data that was just written to the actual tables,
        // making server→device sync completely non-functional.
        if ($syncRecordId > 0) {
            $this->recordChange(
                $companyId,
                $userId,
                $deviceId,
                $tableName,
                $syncRecordId,
                $operation,
                $syncData,
                $opUuid
            );
        }

        return $result;
    }

    protected function tableUsesDirectCompanyId(string $tableName): bool
    {
        return in_array($tableName, $this->directCompanyTables, true);
    }

    protected function companyScopedQuery(string $tableName, string $modelClass, int $companyId)
    {
        return match ($tableName) {
            'users' => $modelClass::whereHas('companies', function ($query) use ($companyId) {
                $query->where('companies.id', $companyId);
            }),
            'company_users' => $modelClass::where('company_id', $companyId),
            'transaction_lines' => $modelClass::whereHas('transaction', function ($query) use ($companyId) {
                $query->where('company_id', $companyId);
            }),
            'payment_in_lines' => $modelClass::whereHas('paymentIn', function ($query) use ($companyId) {
                $query->where('company_id', $companyId);
            }),
            'payment_out_lines' => $modelClass::whereHas('paymentOut', function ($query) use ($companyId) {
                $query->where('company_id', $companyId);
            }),
            default => $modelClass::where('company_id', $companyId),
        };
    }

    /**
     * Get model class for table name
     */
    protected function getModelClass(string $tableName): ?string
    {
        $mappings = [
            'parties' => \App\Models\Party::class,
            'products' => \App\Models\Product::class,
            'invoices' => \App\Models\Invoice::class,
            'transactions' => \App\Models\Transaction::class,
            'transaction_lines' => \App\Models\TransactionLine::class,
            'accounts' => \App\Models\Account::class,
            'account_transactions' => \App\Models\AccountTransaction::class,
            'payment_accounts' => \App\Models\PaymentAccount::class,
            'payment_ins' => \App\Models\PaymentIn::class,
            'payment_in_lines' => \App\Models\PaymentInLine::class,
            'payment_outs' => \App\Models\PaymentOut::class,
            'payment_out_lines' => \App\Models\PaymentOutLine::class,
            'stock_ledgers' => \App\Models\StockLedger::class,
            'units_of_measure' => \App\Models\UnitOfMeasure::class,
            'item_categories' => \App\Models\ItemCategory::class,
            'users' => \App\Models\User::class,
            'company_users' => \App\Models\CompanyUser::class,
        ];

        return $mappings[$tableName] ?? null;
    }

    /**
     * Get current version for a company
     */
    public function getCurrentVersion(int $companyId): int
    {
        $syncVersion = SyncVersion::where('company_id', $companyId)->first();
        return $syncVersion ? $syncVersion->current_version : 0;
    }

    /**
     * Update device sync status
     */
    protected function updateDeviceSyncStatus(
        int $companyId,
        string $deviceId,
        int $version
    ): void {
        DeviceSyncStatus::updateOrCreate(
            [
                'company_id' => $companyId,
                'device_id' => $deviceId,
            ],
            [
                'last_sync_version' => $version,
                'last_sync_at' => now(),
            ]
        );
    }

    /**
     * Get sync status for a device
     */
    public function getSyncStatus(int $companyId, string $deviceId): array
    {
        $deviceStatus = DeviceSyncStatus::where('company_id', $companyId)
            ->where('device_id', $deviceId)
            ->first();

        $currentVersion = $this->getCurrentVersion($companyId);

        $pendingChanges = SyncChange::where('company_id', $companyId)
            ->where('version', '>', $deviceStatus?->last_sync_version ?? 0)
            ->count();

        return [
            'device_id' => $deviceId,
            'last_sync_version' => $deviceStatus?->last_sync_version ?? 0,
            'current_version' => $currentVersion,
            'pending_changes' => $pendingChanges,
            'last_sync_at' => $deviceStatus?->last_sync_at?->toIso8601String(),
            'is_synced' => $pendingChanges === 0,
        ];
    }
}
