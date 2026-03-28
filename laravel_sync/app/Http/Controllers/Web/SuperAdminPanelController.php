<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\ClientBillingRecord;
use App\Models\Company;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\View\View;

class SuperAdminPanelController extends Controller
{
    public function index(): RedirectResponse
    {
        return redirect()->route('super-admin.overview');
    }

    public function overview(): View
    {
        $summary = $this->loadSummary();

        $expiringSoonClients = User::query()
            ->where('role', 'admin')
            ->whereColumn('subscriber_id', 'id')
            ->whereNotNull('subscription_expires_at')
            ->whereBetween('subscription_expires_at', [now(), now()->addDays(30)])
            ->orderBy('subscription_expires_at')
            ->limit(10)
            ->get();

        $recentBilling = ClientBillingRecord::query()
            ->with('clientAdmin:id,full_name,email')
            ->latest('paid_on')
            ->latest('id')
            ->limit(12)
            ->get();

        return view('super-admin.overview', [
            'summary' => $summary,
            'expiringSoonClients' => $expiringSoonClients,
            'recentBilling' => $recentBilling,
        ]);
    }

    public function registerClientPage(): View
    {
        return view('super-admin.register', [
            'summary' => $this->loadSummary(),
        ]);
    }

    public function clientsPage(): View
    {
        $clientsData = $this->loadClientsData();

        return view('super-admin.clients', [
            'clients' => $clientsData['clients'],
            'companyCounts' => $clientsData['companyCounts'],
            'activeCompanyCounts' => $clientsData['activeCompanyCounts'],
        ]);
    }

    public function clientManagementPage(User $client): View
    {
        $this->assertClientAdmin($client);

        $clientsData = $this->loadClientsData();

        $client = User::query()
            ->whereKey($client->id)
            ->with(['clientBillingRecords' => function ($query) {
                $query->latest('paid_on')->latest('id');
            }])
            ->withCount([
                'tenantUsers as managed_users_count',
                'tenantUsers as active_users_count' => function ($query) {
                    $query->where('is_active', true);
                },
            ])
            ->firstOrFail();

        return view('super-admin.client_manage', [
            'client' => $client,
            'companyCount' => (int) ($clientsData['companyCounts'][$client->id] ?? 0),
            'activeCompanyCount' => (int) ($clientsData['activeCompanyCounts'][$client->id] ?? 0),
        ]);
    }

    public function billingPage(): View
    {
        $clientsData = $this->loadClientsData();

        $billingRecords = ClientBillingRecord::query()
            ->with([
                'clientAdmin:id,full_name,email',
                'createdBy:id,full_name',
            ])
            ->latest('paid_on')
            ->latest('id')
            ->paginate(50);

        return view('super-admin.billing', [
            'clients' => $clientsData['clients'],
            'billingRecords' => $billingRecords,
        ]);
    }

    public function storeClient(Request $request): RedirectResponse
    {
        $data = $request->validate([
            'full_name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            'max_companies' => ['required', 'integer', 'min:1', 'max:1000'],
            'subscription_expires_at' => ['nullable', 'date'],
        ]);

        DB::transaction(function () use ($data) {
            $client = User::create([
                'email' => $data['email'],
                'full_name' => $data['full_name'],
                'role' => 'admin',
                'subscriber_id' => null,
                'max_companies' => (int) $data['max_companies'],
                'subscription_expires_at' => $data['subscription_expires_at'] ?? null,
                'password' => Hash::make($data['password']),
                'is_active' => true,
            ]);

            $client->subscriber_id = $client->id;
            $client->save();
        });

        return back()->with('status', 'Client admin registered successfully.');
    }

    public function updateClient(Request $request, User $client): RedirectResponse
    {
        $this->assertClientAdmin($client);

        $data = $request->validate([
            'max_companies' => ['required', 'integer', 'min:1', 'max:1000'],
            'subscription_expires_at' => ['nullable', 'date'],
        ]);

        $client->update([
            'max_companies' => (int) $data['max_companies'],
            'subscription_expires_at' => $data['subscription_expires_at'] ?? null,
        ]);

        return back()->with('status', 'Client settings updated.');
    }

    public function toggleClientStatus(User $client): RedirectResponse
    {
        $this->assertClientAdmin($client);

        $client->is_active = !$client->is_active;
        $client->save();

        return back()->with('status', 'Client status updated.');
    }

    public function extendSubscription(Request $request, User $client): RedirectResponse
    {
        $this->assertClientAdmin($client);

        $data = $request->validate([
            'days' => ['required', 'integer', 'min:1', 'max:3650'],
        ]);

        $baseDate = $client->subscription_expires_at !== null && $client->subscription_expires_at->isFuture()
            ? $client->subscription_expires_at->copy()
            : now();

        $client->subscription_expires_at = $baseDate->addDays((int) $data['days']);
        $client->save();

        return back()->with('status', 'Subscription extended successfully.');
    }

    public function storeBillingRecord(Request $request, User $client): RedirectResponse
    {
        $this->assertClientAdmin($client);

        $data = $request->validate([
            'amount' => ['required', 'numeric', 'min:0.01'],
            'payment_method' => ['required', 'string', Rule::in(['bank_transfer', 'cash', 'card', 'online'])],
            'paid_on' => ['required', 'date'],
            'notes' => ['nullable', 'string', 'max:1000'],
        ]);

        ClientBillingRecord::create([
            'client_admin_id' => $client->id,
            'created_by_user_id' => (int) $request->user()->id,
            'amount' => (float) $data['amount'],
            'payment_method' => $data['payment_method'],
            'paid_on' => $data['paid_on'],
            'notes' => $data['notes'] ?? null,
        ]);

        return back()->with('status', 'Billing record added successfully.');
    }

    public function destroyClient(User $client): RedirectResponse
    {
        $this->assertClientAdmin($client);

        $hasCompanies = Company::query()
            ->where('subscriber_id', $client->id)
            ->exists();

        $hasTenantUsers = User::query()
            ->where('subscriber_id', $client->id)
            ->where('id', '!=', $client->id)
            ->exists();

        if ($hasCompanies || $hasTenantUsers) {
            return back()->withErrors([
                'client' => 'Client cannot be deleted while companies or tenant users exist.',
            ]);
        }

        DB::transaction(function () use ($client) {
            ClientBillingRecord::query()
                ->where('client_admin_id', $client->id)
                ->delete();

            $client->delete();
        });

        return redirect()
            ->route('super-admin.clients')
            ->with('status', 'Client deleted successfully.');
    }

    private function loadSummary(): array
    {
        $clients = User::query()
            ->where('role', 'admin')
            ->whereColumn('subscriber_id', 'id')
            ->get();

        return [
            'registered_clients' => $clients->count(),
            'active_clients' => $clients->where('is_active', true)->count(),
            'expired_clients' => $clients->filter(function (User $client) {
                return $client->subscription_expires_at !== null
                    && $client->subscription_expires_at->isPast();
            })->count(),
            'total_billed' => (float) ClientBillingRecord::query()->sum('amount'),
        ];
    }

    private function loadClientsData(): array
    {
        $clients = User::query()
            ->where('role', 'admin')
            ->whereColumn('subscriber_id', 'id')
            ->with(['clientBillingRecords' => function ($query) {
                $query->latest('paid_on')->latest('id');
            }])
            ->withCount([
                'tenantUsers as managed_users_count',
                'tenantUsers as active_users_count' => function ($query) {
                    $query->where('is_active', true);
                },
            ])
            ->orderBy('full_name')
            ->get();

        $companyCounts = Company::query()
            ->selectRaw('subscriber_id, COUNT(*) as total_companies')
            ->groupBy('subscriber_id')
            ->pluck('total_companies', 'subscriber_id');

        $activeCompanyCounts = Company::query()
            ->selectRaw('subscriber_id, COUNT(*) as active_companies')
            ->where('is_active', true)
            ->groupBy('subscriber_id')
            ->pluck('active_companies', 'subscriber_id');

        return [
            'clients' => $clients,
            'companyCounts' => $companyCounts,
            'activeCompanyCounts' => $activeCompanyCounts,
        ];
    }

    private function assertClientAdmin(User $client): void
    {
        abort_unless(
            $client->role === 'admin' && (int) $client->subscriber_id === (int) $client->id,
            404
        );
    }
}
