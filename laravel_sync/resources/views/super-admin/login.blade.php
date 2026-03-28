@extends('layouts.super_admin')

@section('title', 'Super Admin Login')

@section('content')
    <div style="min-height: calc(100vh - 48px); display: grid; place-items: center;">
        <div class="card pad" style="width: min(100%, 480px);">
            <div class="brand" style="margin-bottom: 22px;">
                <p style="margin: 0; letter-spacing: 0.18em; text-transform: uppercase;">Octavision</p>
                <h1>Super Admin Control Panel</h1>
                <p>Separate Laravel portal for SaaS client management.</p>
            </div>

            @if ($errors->any())
                <div class="errors">
                    @foreach ($errors->all() as $error)
                        <div>{{ $error }}</div>
                    @endforeach
                </div>
            @endif

            <form method="post" action="{{ route('super-admin.login.store') }}" class="grid">
                @csrf
                <div>
                    <label for="email">Email</label>
                    <input id="email" type="email" name="email" value="{{ old('email') }}" required autofocus>
                </div>
                <div>
                    <label for="password">Password</label>
                    <input id="password" type="password" name="password" required>
                </div>
                <label style="display:flex; gap:8px; align-items:center; margin: 0; color: var(--muted);">
                    <input type="checkbox" name="remember" value="1" style="width:auto;">
                    <span>Keep me signed in</span>
                </label>
                <button class="btn-primary" type="submit">Sign In as Super Admin</button>
            </form>
        </div>
    </div>
@endsection
