<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

class EnsureSuperAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (!$user) {
            return redirect()->route('super-admin.login');
        }

        if ($user->role !== 'super_admin') {
            abort(403, 'Super admin access only.');
        }

        if (!$user->is_active) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return redirect()
                ->route('super-admin.login')
                ->withErrors(['email' => 'This super admin account is inactive.']);
        }

        return $next($request);
    }
}
