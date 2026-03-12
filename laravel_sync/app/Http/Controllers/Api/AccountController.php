<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Account;
use App\Models\AccountTransaction;
use Illuminate\Http\Request;

class AccountController extends Controller
{
    private function hasAccess(Request $request, int $companyId): bool
    {
        return $request->user()->companies()
            ->where('companies.id', $companyId)
            ->exists();
    }

    /** GET /api/accounts?company_id= */
    public function index(Request $request)
    {
        $request->validate(['company_id' => 'required|integer']);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $accounts = Account::where('company_id', $request->company_id)
            ->where('is_active', true)
            ->orderBy('code')
            ->get();

        return response()->json(['success' => true, 'accounts' => $accounts]);
    }

    /**
     * GET /api/account-transactions?company_id=&account_id=&party_id=
     * Returns the ledger entries for a given account (or party).
     */
    public function transactions(Request $request)
    {
        $request->validate([
            'company_id' => 'required|integer',
            'account_id' => 'nullable|integer',
            'party_id'   => 'nullable|integer',
        ]);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $query = AccountTransaction::where('company_id', $request->company_id)
            ->orderBy('transaction_date');

        if ($request->account_id) {
            $query->where('account_id', $request->account_id);
        }
        if ($request->party_id) {
            $query->where('party_id', $request->party_id);
        }

        return response()->json([
            'success'      => true,
            'transactions' => $query->get(),
        ]);
    }

    /**
     * GET /api/accounts/balance?company_id=&party_id=
     * Returns the net AR / AP balance for a specific party.
     */
    public function partyBalance(Request $request)
    {
        $request->validate([
            'company_id' => 'required|integer',
            'party_id'   => 'required|integer',
        ]);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        // Aggregate debit – credit for this party across AR (1200) and AP (2000) accounts
        $balance = AccountTransaction::where('company_id', $request->company_id)
            ->where('party_id', $request->party_id)
            ->selectRaw('SUM(debit) - SUM(credit) as balance')
            ->value('balance') ?? 0;

        return response()->json([
            'success' => true,
            'balance' => (float) $balance,
        ]);
    }
}
