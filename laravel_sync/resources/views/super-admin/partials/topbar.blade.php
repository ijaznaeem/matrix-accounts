<div class="topbar">
    <div class="brand">
        <p>Octavision SaaS</p>
        <h1>{{ $title }}</h1>
        <p>{{ $subtitle }}</p>
    </div>
    <div class="actions">
        <div class="muted">Signed in as {{ auth()->user()->full_name }}</div>
        <form method="post" action="{{ route('super-admin.logout') }}">
            @csrf
            <button class="btn-secondary" type="submit">Logout</button>
        </form>
    </div>
</div>
