@extends('layouts.super_admin')

@section('title', 'Overview | Octavision Super Admin')

@section('content')
    @include('super-admin.partials.topbar', [
        'title' => 'Platform Overview',
        'subtitle' => 'Monitor client subscriptions, renewals, and billing performance.',
    ])

    @include('super-admin.partials.alerts')

    <div class="grid grid-4" style="margin-bottom: 18px;">
        <div class="stat card">
            <span class="value">{{ $summary['registered_clients'] }}</span>
            <span class="label">Registered client admins</span>
        </div>
        <div class="stat card">
            <span class="value">{{ $summary['active_clients'] }}</span>
            <span class="label">Active subscriptions</span>
        </div>
        <div class="stat card">
            <span class="value">{{ $summary['expired_clients'] }}</span>
            <span class="label">Expired clients</span>
        </div>
        <div class="stat card">
            <span class="value">PKR {{ number_format($summary['total_billed'], 2) }}</span>
            <span class="label">Recorded billing total</span>
        </div>
    </div>

    <div class="grid grid-2">
        <section class="card pad">
            <h2 class="section-title">Expiring in Next 30 Days</h2>
            @if ($expiringSoonClients->isEmpty())
                <div class="muted">No clients are expiring in the next 30 days.</div>
            @else
                <table class="billing-table">
                    <thead>
                        <tr>
                            <th>Client Admin</th>
                            <th>Email</th>
                            <th>Expiry</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($expiringSoonClients as $client)
                            <tr>
                                <td>{{ $client->full_name }}</td>
                                <td>{{ $client->email }}</td>
                                <td>{{ optional($client->subscription_expires_at)->format('d M Y') }}</td>
                                <td>{{ $client->is_active ? 'Active' : 'Inactive' }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            @endif
        </section>

        <section class="card pad">
            <h2 class="section-title">Recent Billing</h2>
            @if ($recentBilling->isEmpty())
                <div class="muted">No billing transactions recorded yet.</div>
            @else
                <table class="billing-table">
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Client</th>
                            <th>Method</th>
                            <th>Amount</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($recentBilling as $record)
                            <tr>
                                <td>{{ $record->paid_on?->format('d M Y') }}</td>
                                <td>{{ $record->clientAdmin?->full_name ?? '—' }}</td>
                                <td>{{ str_replace('_', ' ', ucfirst($record->payment_method)) }}</td>
                                <td>PKR {{ number_format((float) $record->amount, 2) }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            @endif
        </section>
    </div>
@endsection
