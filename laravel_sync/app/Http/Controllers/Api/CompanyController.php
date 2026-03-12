<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

class CompanyController extends Controller
{
    /**
     * List all companies the authenticated user belongs to.
     * GET /api/companies
     */
    public function index(Request $request)
    {
        $companies = $request->user()
            ->companies()
            ->wherePivot('is_active', true)
            ->withPivot('role')
            ->get()
            ->map(fn ($c) => [
                'id'                        => $c->id,
                'name'                      => $c->name,
                'primary_currency'          => $c->primary_currency,
                'financial_year_start_month' => $c->financial_year_start_month,
                'role'                      => $c->pivot->role,
                'is_active'                 => $c->is_active,
            ]);

        return response()->json([
            'success'   => true,
            'companies' => $companies,
        ]);
    }
}
