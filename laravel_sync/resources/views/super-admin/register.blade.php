@extends('layouts.super_admin')

@section('title', 'Register Client Admin | Octavision Super Admin')

@section('content')
    @include('super-admin.partials.topbar', [
        'title' => 'Register Client Admin',
        'subtitle' => 'Create a new tenant owner account with company limits and subscription policy.',
    ])

    @include('super-admin.partials.alerts')

    <div class="grid grid-2">
        <section class="card pad">
            <h2 class="section-title">Create Client Admin</h2>
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
                <div class="muted">This portal is isolated for Octavision platform operations.</div>
                <div class="muted">Only users with the super_admin role can sign in here.</div>
                <div class="muted">Client admins continue managing business users from VEYO only.</div>
                <div class="muted">After onboarding, use Client Management to update limits, status, and expiry.</div>
            </div>
        </section>
    </div>
@endsection
