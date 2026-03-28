@extends('layouts.super_admin')

@section('title', 'Manage Client | Octavision Super Admin')

@section('content')
    @include('super-admin.partials.topbar', [
        'title' => 'Manage Client',
        'subtitle' => 'Update limits, activation, subscription extension, and billing for one selected client.',
    ])

    @include('super-admin.partials.alerts')

    @php
        $isExpired = $client->subscription_expires_at && $client->subscription_expires_at->isPast();
        $totalBilled = (float) $client->clientBillingRecords->sum('amount');
    @endphp

    <section class="card pad" style="margin-bottom: 16px;">
        <div class="client-head" style="margin-bottom: 10px;">
            <div>
                <h2 class="section-title" style="margin-bottom: 6px;">{{ $client->full_name }}</h2>
                <div class="muted">{{ $client->email }}</div>
            </div>
            <a href="{{ route('super-admin.clients') }}" class="btn-secondary" style="display:inline-block; text-decoration:none;">Back to Client List</a>
        </div>

        <div class="meta">
            <div class="item">Allowed Companies: {{ $client->max_companies }}</div>
            <div class="item">Current Companies: {{ $companyCount }}</div>
            <div class="item">Active Companies: {{ $activeCompanyCount }}</div>
            <div class="item">Managed Users: {{ $client->managed_users_count }}</div>
            <div class="item">Active Users: {{ $client->active_users_count }}</div>
            <div class="item">Billing Total: PKR {{ number_format($totalBilled, 2) }}</div>
            <div class="item">
                Status:
                @if ($client->is_active)
                    Active
                @else
                    Inactive
                @endif
            </div>
            <div class="item">
                Expiry:
                @if ($isExpired)
                    Expired
                @elseif ($client->subscription_expires_at)
                    {{ $client->subscription_expires_at->format('d M Y') }}
                @else
                    Not set
                @endif
            </div>
        </div>
    </section>

    <section class="row-forms" style="margin-bottom: 16px;">
        <form method="post" action="{{ route('super-admin.clients.update', $client) }}" class="card pad">
            @csrf
            @method('PATCH')
            <h3 style="margin-top:0;">Client Limits</h3>
            <div class="grid">
                <div>
                    <label>Allowed companies</label>
                    <input type="number" name="max_companies" min="1" value="{{ $client->max_companies }}" required>
                </div>
                <div>
                    <label>Expiry date</label>
                    <input type="date" name="subscription_expires_at" value="{{ optional($client->subscription_expires_at)->format('Y-m-d') }}">
                </div>
                <button class="btn-primary" type="submit">Save Settings</button>
            </div>
        </form>

        <div class="grid">
            <form method="post" action="{{ route('super-admin.clients.status', $client) }}" class="card pad">
                @csrf
                @method('PATCH')
                <h3 style="margin-top:0;">Activation</h3>
                <p class="muted">Toggle whether this client admin can access VEYO.</p>
                <button class="{{ $client->is_active ? 'btn-danger' : 'btn-ok' }}" type="submit">
                    {{ $client->is_active ? 'Deactivate Client' : 'Activate Client' }}
                </button>
            </form>

            <form method="post" action="{{ route('super-admin.clients.extend', $client) }}" class="card pad">
                @csrf
                <h3 style="margin-top:0;">Extend Subscription</h3>
                <div class="grid">
                    <div>
                        <label>Days</label>
                        <input type="number" name="days" min="1" value="30" required>
                    </div>
                    <button class="btn-secondary" type="submit">Extend</button>
                </div>
            </form>
        </div>

        <form method="post" action="{{ route('super-admin.clients.billing.store', $client) }}" class="card pad">
            @csrf
            <h3 style="margin-top:0;">Add Billing Record</h3>
            <div class="grid">
                <div>
                    <label>Amount</label>
                    <input type="number" name="amount" min="0.01" step="0.01" required>
                </div>
                <div>
                    <label>Payment method</label>
                    <select name="payment_method" required>
                        <option value="bank_transfer">Bank Transfer</option>
                        <option value="cash">Cash</option>
                        <option value="card">Card</option>
                        <option value="online">Online</option>
                    </select>
                </div>
                <div>
                    <label>Paid on</label>
                    <input type="date" name="paid_on" value="{{ now()->format('Y-m-d') }}" required>
                </div>
                <div>
                    <label>Notes</label>
                    <textarea name="notes"></textarea>
                </div>
                <button class="btn-primary" type="submit">Save Billing</button>
            </div>
        </form>
    </section>

    <section class="card pad">
        <h3 style="margin-top:0;">Billing History</h3>
        @if ($client->clientBillingRecords->isEmpty())
            <div class="muted">No billing records yet.</div>
        @else
            <table class="billing-table">
                <thead>
                    <tr>
                        <th>Date</th>
                        <th>Amount</th>
                        <th>Method</th>
                        <th>Notes</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach ($client->clientBillingRecords as $record)
                        <tr>
                            <td>{{ $record->paid_on?->format('d M Y') }}</td>
                            <td>PKR {{ number_format((float) $record->amount, 2) }}</td>
                            <td>{{ str_replace('_', ' ', ucfirst($record->payment_method)) }}</td>
                            <td>{{ $record->notes ?: '—' }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        @endif
    </section>
@endsection
