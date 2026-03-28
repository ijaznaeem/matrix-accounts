<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>@yield('title', 'Octavision Super Admin')</title>
    <style>
        :root {
            --bg: #f4efe8;
            --surface: #fffdf8;
            --ink: #1f2933;
            --muted: #677281;
            --line: #ddd4c8;
            --accent: #0f766e;
            --accent-2: #b45309;
            --danger: #b42318;
            --ok: #166534;
            --shadow: 0 14px 40px rgba(33, 24, 16, 0.08);
        }

        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: Georgia, 'Times New Roman', serif;
            color: var(--ink);
            scroll-behavior: smooth;
            background:
                radial-gradient(circle at top left, rgba(180, 83, 9, 0.10), transparent 22%),
                radial-gradient(circle at top right, rgba(15, 118, 110, 0.10), transparent 28%),
                linear-gradient(180deg, #f7f2ea 0%, var(--bg) 100%);
        }

        a { color: inherit; }
        .shell {
            max-width: 1380px;
            margin: 0 auto;
            padding: 24px;
        }

        .layout {
            display: grid;
            grid-template-columns: 280px minmax(0, 1fr);
            gap: 18px;
            align-items: start;
        }

        .sidebar {
            position: sticky;
            top: 16px;
            padding: 18px;
            border-radius: 22px;
            background: rgba(255, 253, 248, 0.92);
            border: 1px solid rgba(221, 212, 200, 0.9);
            box-shadow: var(--shadow);
            backdrop-filter: blur(10px);
        }

        .sidebar h3 {
            margin: 0 0 12px;
            font-size: 18px;
        }

        .sidebar .menu {
            display: grid;
            gap: 8px;
            margin-bottom: 14px;
        }

        .sidebar .menu a {
            display: block;
            text-decoration: none;
            padding: 10px 12px;
            border-radius: 12px;
            border: 1px solid #e8dccd;
            background: #fffefb;
            color: var(--ink);
            font-size: 14px;
        }

        .sidebar .menu a:hover {
            border-color: #c8b69f;
            background: #faf4ea;
        }

        .sidebar .menu a.active {
            border-color: #bda787;
            background: linear-gradient(145deg, #f8efe3, #f2e5d5);
            color: #4a3316;
            font-weight: 700;
        }

        .sidebar .small {
            font-size: 12px;
            color: var(--muted);
            line-height: 1.45;
        }

        .topbar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
            margin-bottom: 24px;
            padding: 18px 22px;
            background: rgba(255, 253, 248, 0.9);
            border: 1px solid rgba(221, 212, 200, 0.9);
            border-radius: 20px;
            box-shadow: var(--shadow);
            backdrop-filter: blur(10px);
        }

        .brand h1 {
            margin: 0;
            font-size: 28px;
            line-height: 1.1;
        }

        .brand p {
            margin: 6px 0 0;
            color: var(--muted);
            font-size: 14px;
        }

        .actions {
            display: flex;
            gap: 12px;
            align-items: center;
            flex-wrap: wrap;
        }

        .card {
            background: var(--surface);
            border: 1px solid var(--line);
            border-radius: 22px;
            box-shadow: var(--shadow);
        }

        .pad { padding: 20px; }
        .grid { display: grid; gap: 18px; }
        .grid-4 { grid-template-columns: repeat(4, minmax(0, 1fr)); }
        .grid-2 { grid-template-columns: 1.2fr 1fr; }
        .grid-3 { grid-template-columns: repeat(3, minmax(0, 1fr)); }

        .stat {
            padding: 18px;
            border-radius: 18px;
            background: linear-gradient(145deg, rgba(255,255,255,0.96), rgba(246, 239, 231, 0.96));
            border: 1px solid var(--line);
        }

        .stat .value {
            display: block;
            font-size: 30px;
            font-weight: 700;
            margin-bottom: 8px;
        }

        .stat .label {
            display: block;
            color: var(--muted);
            font-size: 14px;
        }

        .form-grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 14px;
        }

        .field,
        input,
        select,
        textarea,
        button {
            font: inherit;
        }

        input,
        select,
        textarea {
            width: 100%;
            padding: 12px 14px;
            border-radius: 12px;
            border: 1px solid #cdbfaf;
            background: #fffefb;
            color: var(--ink);
        }

        textarea { min-height: 88px; resize: vertical; }
        label {
            display: block;
            margin-bottom: 6px;
            font-size: 13px;
            color: var(--muted);
        }

        button {
            border: 0;
            border-radius: 12px;
            padding: 12px 16px;
            cursor: pointer;
            font-weight: 700;
        }

        .btn-primary { background: var(--accent); color: white; }
        .btn-secondary { background: #efe5d8; color: #573814; }
        .btn-danger { background: var(--danger); color: white; }
        .btn-ok { background: var(--ok); color: white; }

        .section-title {
            margin: 0 0 14px;
            font-size: 20px;
        }

        .muted { color: var(--muted); }
        .flash {
            margin-bottom: 16px;
            padding: 14px 16px;
            border-radius: 14px;
            border: 1px solid #b7e2c8;
            background: #eefbf2;
            color: #155724;
        }

        .errors {
            margin-bottom: 16px;
            padding: 14px 16px;
            border-radius: 14px;
            border: 1px solid #f0c2c2;
            background: #fff2f2;
            color: #8a1c1c;
        }

        .clients {
            display: grid;
            gap: 18px;
        }

        .client-head {
            display: flex;
            justify-content: space-between;
            align-items: start;
            gap: 16px;
            margin-bottom: 16px;
        }

        .pill {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 7px 12px;
            border-radius: 999px;
            font-size: 12px;
            font-weight: 700;
            border: 1px solid transparent;
        }

        .pill-ok { background: #edf9f0; color: var(--ok); border-color: #b7e2c8; }
        .pill-off { background: #fff2f2; color: var(--danger); border-color: #efc4c4; }
        .pill-warn { background: #fff7e8; color: var(--accent-2); border-color: #f1dbb2; }

        .meta {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 16px;
        }

        .meta .item {
            padding: 8px 10px;
            border-radius: 10px;
            border: 1px solid var(--line);
            background: #fcfaf5;
            font-size: 13px;
        }

        .row-forms {
            display: grid;
            grid-template-columns: 1.2fr 0.9fr 1fr;
            gap: 14px;
            align-items: start;
        }

        .billing-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 14px;
            font-size: 14px;
        }

        .billing-table th,
        .billing-table td {
            text-align: left;
            padding: 10px 8px;
            border-bottom: 1px solid #eadfce;
            vertical-align: top;
        }

        @media (max-width: 1100px) {
            .layout {
                grid-template-columns: 1fr;
            }

            .sidebar {
                position: static;
            }

            .grid-4, .grid-2, .grid-3, .row-forms, .form-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="shell">
        @php
            $showSidebar = auth()->check() && request()->routeIs('super-admin.*') && !request()->routeIs('super-admin.login*');
        @endphp

        @if ($showSidebar)
            <div class="layout">
                <aside class="sidebar">
                    <h3>Menu</h3>
                    <nav class="menu">
                        <a class="{{ request()->routeIs('super-admin.dashboard') || request()->routeIs('super-admin.overview') ? 'active' : '' }}" href="{{ route('super-admin.overview') }}">Overview</a>
                        <a class="{{ request()->routeIs('super-admin.register') ? 'active' : '' }}" href="{{ route('super-admin.register') }}">Register Client Admin</a>
                        <a class="{{ request()->routeIs('super-admin.clients') ? 'active' : '' }}" href="{{ route('super-admin.clients') }}">Client Management</a>
                        <a class="{{ request()->routeIs('super-admin.billing') ? 'active' : '' }}" href="{{ route('super-admin.billing') }}">Billing Records</a>
                    </nav>
                    <div class="small">
                        This panel is isolated for Octavision super admins. Client admins manage users and routes from the VEYO app.
                    </div>
                </aside>
                <main>
                    @yield('content')
                </main>
            </div>
        @else
            <main>
                @yield('content')
            </main>
        @endif
    </div>
</body>
</html>
