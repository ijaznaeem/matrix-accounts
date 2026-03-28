@extends('layouts.super_admin')

@section('title', 'Billing Records | Octavision Super Admin')

@section('content')
    @include('super-admin.partials.topbar', [
        'title' => 'Billing Records',
        'subtitle' => 'Record client payments and maintain a complete subscription billing history.',
    ])

    @include('super-admin.partials.alerts')

    <div class="grid" style="margin-bottom: 18px;">
        <section class="card pad">
            <h2 class="section-title">Add Billing Record</h2>
            @if ($clients->isEmpty())
                <div class="muted">No client admins available yet. Register a client first.</div>
            @else
                <div class="grid grid-2">
                    @foreach ($clients as $client)
                        <form method="post" action="{{ route('super-admin.clients.billing.store', $client) }}" class="card pad">
                            @csrf
                            <h3 style="margin-top:0; margin-bottom: 8px;">{{ $client->full_name }}</h3>
                            <div class="muted" style="margin-bottom: 10px;">{{ $client->email }}</div>
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
                    @endforeach
                </div>
            @endif
        </section>
    </div>

    <section class="card pad">
        <h2 class="section-title">Billing History</h2>
        @if ($billingRecords->isEmpty())
            <div class="muted">No billing records yet.</div>
        @else
            <table class="billing-table">
                <thead>
                    <tr>
                        <th>Date</th>
                        <th>Client</th>
                        <th>Method</th>
                        <th>Amount</th>
                        <th>Recorded By</th>
                        <th>Notes</th>
                    </tr>
                </thead>
                <tbody>
                    @foreach ($billingRecords as $record)
                        <tr>
                            <td>{{ $record->paid_on?->format('d M Y') }}</td>
                            <td>{{ $record->clientAdmin?->full_name ?? '—' }}</td>
                            <td>{{ str_replace('_', ' ', ucfirst($record->payment_method)) }}</td>
                            <td>PKR {{ number_format((float) $record->amount, 2) }}</td>
                            <td>{{ $record->createdBy?->full_name ?? '—' }}</td>
                            <td>{{ $record->notes ?: '—' }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>

            <div style="margin-top: 14px;">
                {{ $billingRecords->links() }}
            </div>
        @endif
    </section>
@endsection
