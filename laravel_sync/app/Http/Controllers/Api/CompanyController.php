<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Company;
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

    /**
     * Create a new company and associate it with the authenticated user.
     * POST /api/companies
     */
    public function store(Request $request)
    {
        $request->validate([
            'name' => 'required|string|max:255',
            'primary_currency' => 'nullable|string|max:10',
            'financial_year_start_month' => 'nullable|integer|min:1|max:12',
        ]);

        $company = Company::create([
            'name' => $request->name,
            'primary_currency' => $request->primary_currency ?? 'PKR',
            'financial_year_start_month' => $request->financial_year_start_month ?? 1,
            'is_active' => true,
        ]);

        // Attach user as admin
        $request->user()->companies()->attach($company->id, [
            'role' => 'admin',
            'is_active' => true,
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Company created successfully',
            'company' => [
                'id' => $company->id,
                'name' => $company->name,
                'primary_currency' => $company->primary_currency,
                'financial_year_start_month' => $company->financial_year_start_month,
                'role' => 'admin',
                'is_active' => $company->is_active,
            ],
        ], 201);
    }
}
