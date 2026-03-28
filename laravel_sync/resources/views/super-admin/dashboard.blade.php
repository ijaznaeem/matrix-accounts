@extends('layouts.super_admin')

@section('title', 'Octavision Control Panel')

@section('content')
    <div class="topbar">
        <div class="brand">
            <p>Octavision SaaS</p>
            <h1>Client Control Panel</h1>
            <p>Manage tenant admins, company limits, subscriptions, activation, and billing.</p>
        </div>
        <div class="actions">
            <div class="muted">Signed in as {{ auth()->user()->full_name }}</div>
            <form method="post" action="{{ route('super-admin.logout') }}">
                @csrf
                <button class="btn-secondary" type="submit">Logout</button>
            </form>
        </div>
    </div>

    @if (session('status'))
        <div class="flash">{{ session('status') }}</div>
    @endif

    @if ($errors->any())
        <div class="errors">
            @foreach ($errors->all() as $error)
                <div>{{ $error }}</div>
            @endforeach
        </div>
    @endif

    <div id="overview" class="grid grid-4" style="margin-bottom: 18px;">
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

    <div class="grid grid-2" style="margin-bottom: 18px;">
        <section id="register-client" class="card pad">
            <h2 class="section-title">Register Client Admin</h2>
            <form method="post" action="{{ route('super-admin.clients.store') }}" class="grid">
                @csrf
                <div class="form-grid">
                    <div>
                        <label for="full_name">Admin name</label>
                        <input id="full_name" name="full_name" value="{{ old('full_name') }}" required>
                    </div>
                    <div>
                        <label for="email">Admin email</label>
                        <input id="email" type="email" name="email" value="{{ old('email') }}" required>
                    </div>
                    <div>
                        <label for="password">Password</label>
                        <input id="password" type="password" name="password" required>
                    </div>
                    <div>
                        <label for="password_confirmation">Confirm password</label>
                        <input id="password_confirmation" type="password" name="password_confirmation" required>
                    </div>
                    <div>
                        <label for="max_companies">Allowed companies</label>
                        <input id="max_companies" type="number" name="max_companies" min="1" value="{{ old('max_companies', 5) }}" required>
                    </div>
                    <div>
                        <label for="subscription_expires_at">Subscription expiry</label>
                        <input id="subscription_expires_at" type="date" name="subscription_expires_at" value="{{ old('subscription_expires_at') }}">
                    </div>
                </div>
                <button class="btn-primary" type="submit">Create Client Admin</button>
            </form>
        </section>

        <section class="card pad">
            <h2 class="section-title">Access Model</h2>
            <div class="grid">
                <div class="muted">This web panel is isolated from the Flutter app.</div>
                <div class="muted">Only users with the <strong>super_admin</strong> role can sign in here.</div>
                <div class="muted">Client admins continue using the VEYO app and do not access this Laravel portal.</div>
            </div>
        </section>
    </div>

    <section id="client-list" class="clients">
        @forelse ($clients as $client)
            @php
                $isExpired = $client->subscription_expires_at && $client->subscription_expires_at->isPast();
                $companyCount = (int) ($companyCounts[$client->id] ?? 0);
                $activeCompanyCount = (int) ($activeCompanyCounts[$client->id] ?? 0);
                $totalBilled = (float) $client->clientBillingRecords->sum('amount');
            @endphp
            <article class="card pad">
                <div class="client-head">
                    <div>
                        <h2 class="section-title" style="margin-bottom: 6px;">{{ $client->full_name }}</h2>
                        <div class="muted">{{ $client->email }}</div>
                    </div>
                    <div style="display:flex; gap:10px; flex-wrap:wrap;">
                        @if ($client->is_active)
                            <span class="pill pill-ok">Active</span>
                        @else
                            <span class="pill pill-off">Inactive</span>
                        @endif

                        @if ($isExpired)
                            <span class="pill pill-warn">Expired</span>
                        @elseif ($client->subscription_expires_at)
                            <span class="pill pill-ok">Expires {{ $client->subscription_expires_at->format('d M Y') }}</span>
                        @else
                            <span class="pill pill-warn">No expiry set</span>
                        @endif
                    </div>
                </div>

                <div class="meta">
                    <div class="item">Allowed Companies: {{ $client->max_companies }}</div>
                    <div class="item">Current Companies: {{ $companyCount }}</div>
                    <div class="item">Active Companies: {{ $activeCompanyCount }}</div>
                    <div class="item">Managed Users: {{ $client->managed_users_count }}</div>
                    <div class="item">Active Users: {{ $client->active_users_count }}</div>
                    <div class="item">Billing Total: PKR {{ number_format($totalBilled, 2) }}</div>
                </div>

                <div class="row-forms">
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
                </div>

                <div @if($loop->first) id="billing-history" @endif class="card pad" style="margin-top: 14px;">
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
                </div>
            </article>
        @empty
            <div class="card pad muted">No client admins registered yet.</div>
        @endforelse
    </section>
@endsection
