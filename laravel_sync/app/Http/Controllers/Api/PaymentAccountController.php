<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PaymentAccount;
use Illuminate\Http\Request;

class PaymentAccountController extends Controller
{
    private function hasAccess(Request $request, int $companyId): bool
    {
        return $request->user()->companies()
            ->where('companies.id', $companyId)
            ->exists();
    }

    /** GET /api/payment-accounts?company_id= */
    public function index(Request $request)
    {
        $request->validate(['company_id' => 'required|integer']);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $accounts = PaymentAccount::where('company_id', $request->company_id)
            ->where('is_active', true)
            ->orderBy('account_name')
            ->get();

        return response()->json(['success' => true, 'payment_accounts' => $accounts]);
    }

    /** POST /api/payment-accounts */
    public function store(Request $request)
    {
        $data = $request->validate([
            'company_id'     => 'required|integer',
            'account_type'   => 'required|in:cash,bank',
            'account_name'   => 'required|string|max:255',
            'bank_name'      => 'nullable|string|max:255',
            'account_number' => 'nullable|string|max:100',
            'ifsc_code'      => 'nullable|string|max:50',
            'icon'           => 'nullable|string|max:50',
            'is_active'      => 'nullable|boolean',
            'is_default'     => 'nullable|boolean',
        ]);

        if (!$this->hasAccess($request, $data['company_id'])) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $account = PaymentAccount::create($data);

        return response()->json([
            'success'         => true,
            'message'         => 'Payment account created successfully',
            'payment_account' => $account,
        ], 201);
    }

    /** PUT /api/payment-accounts/{id} */
    public function update(Request $request, int $id)
    {
        $account = PaymentAccount::findOrFail($id);

        if (!$this->hasAccess($request, $account->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $data = $request->validate([
            'account_name'   => 'sometimes|required|string|max:255',
            'bank_name'      => 'nullable|string|max:255',
            'account_number' => 'nullable|string|max:100',
            'ifsc_code'      => 'nullable|string|max:50',
            'icon'           => 'nullable|string|max:50',
            'is_active'      => 'nullable|boolean',
            'is_default'     => 'nullable|boolean',
        ]);

        $account->update($data);

        return response()->json([
            'success'         => true,
            'message'         => 'Payment account updated successfully',
            'payment_account' => $account,
        ]);
    }
}
