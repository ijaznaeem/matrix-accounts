@extends('layouts.super_admin')

@section('title', 'Client Management | Octavision Super Admin')

@section('content')
    @include('super-admin.partials.topbar', [
        'title' => 'Client Management',
        'subtitle' => 'Start with the client list, then open a dedicated management screen per client.',
    ])

    @include('super-admin.partials.alerts')

    <section class="card pad">
        <div class="client-head" style="margin-bottom: 14px;">
            <div>
                <h2 class="section-title" style="margin-bottom: 6px;">Client CRUD</h2>
                <div class="muted">Create from Register page, read list here, update/manage on click, and delete when allowed.</div>
            </div>
            <a href="{{ route('super-admin.register') }}" class="btn-primary" style="display:inline-block; text-decoration:none;">Create Client</a>
        </div>

        @if ($clients->isEmpty())
            <div class="muted">No client admins registered yet.</div>
        @else
            <table class="billing-table">
                <thead>
                    <tr>
                        <th>Client</th>
                        <th>Status</th>
                        <th>Companies</th>
                        <th>Users</th>
                        <th>Expiry</th>
                        <th>Billing</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach ($clients as $client)
                        @php
                            $companyCount = (int) ($companyCounts[$client->id] ?? 0);
                            $activeCompanyCount = (int) ($activeCompanyCounts[$client->id] ?? 0);
                            $totalBilled = (float) $client->clientBillingRecords->sum('amount');
                            $isExpired = $client->subscription_expires_at && $client->subscription_expires_at->isPast();
                            $canDelete = $companyCount === 0 && (int) $client->managed_users_count === 0;
                        @endphp
                        <tr>
                            <td>
                                <div><strong>{{ $client->full_name }}</strong></div>
                                <div class="muted">{{ $client->email }}</div>
                            </td>
                            <td>
                                @if ($client->is_active)
                                    <span class="pill pill-ok">Active</span>
                                @else
                                    <span class="pill pill-off">Inactive</span>
                                @endif
                            </td>
                            <td>{{ $activeCompanyCount }} / {{ $companyCount }}</td>
                            <td>{{ $client->active_users_count }} / {{ $client->managed_users_count }}</td>
                            <td>
                                @if ($isExpired)
                                    <span class="pill pill-warn">Expired</span>
                                @elseif ($client->subscription_expires_at)
                                    {{ $client->subscription_expires_at->format('d M Y') }}
                                @else
                                    <span class="muted">Not set</span>
                                @endif
                            </td>
                            <td>PKR {{ number_format($totalBilled, 2) }}</td>
                            <td>
                                <div style="display:flex; gap:8px; flex-wrap:wrap; align-items:center;">
                                    <a href="{{ route('super-admin.clients.manage', $client) }}" class="btn-secondary" style="display:inline-block; text-decoration:none;">Manage</a>
                                    <form method="post" action="{{ route('super-admin.clients.destroy', $client) }}" onsubmit="return confirm('Delete this client? This action cannot be undone.');" style="margin:0;">
                                        @csrf
                                        @method('DELETE')
                                        <button type="submit" class="btn-danger" {{ $canDelete ? '' : 'disabled' }}>Delete</button>
                                    </form>
                                </div>
                                @unless ($canDelete)
                                    <div class="muted" style="margin-top: 6px;">Delete available only when no companies and no tenant users exist.</div>
                                @endunless
                            </td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        @endif
    </section>
@endsection
