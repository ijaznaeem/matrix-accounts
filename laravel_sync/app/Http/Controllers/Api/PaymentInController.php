<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PaymentIn;
use App\Models\PaymentInLine;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PaymentInController extends Controller
{
    private function hasAccess(Request $request, int $companyId): bool
    {
        return $request->user()->companies()
            ->where('companies.id', $companyId)
            ->exists();
    }

    /** GET /api/payment-ins?company_id=&party_id= */
    public function index(Request $request)
    {
        $request->validate([
            'company_id' => 'required|integer',
            'party_id'   => 'nullable|integer',
        ]);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $query = PaymentIn::with('lines')
            ->where('company_id', $request->company_id);

        if ($request->party_id) {
            $query->where('party_id', $request->party_id);
        }

        return response()->json([
            'success'     => true,
            'payment_ins' => $query->orderBy('receipt_date', 'desc')->get(),
        ]);
    }

    /** POST /api/payment-ins */
    public function store(Request $request)
    {
        $data = $request->validate([
            'company_id'           => 'required|integer',
            'receipt_no'           => 'required|string|max:100',
            'receipt_date'         => 'required|date',
            'party_id'             => 'required|integer',
            'total_amount'         => 'required|numeric',
            'description'          => 'nullable|string',
            'lines'                => 'required|array|min:1',
            'lines.*.payment_account_id' => 'required|integer',
            'lines.*.amount'       => 'required|numeric',
            'lines.*.reference_no' => 'nullable|string|max:100',
        ]);

        if (!$this->hasAccess($request, $data['company_id'])) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $result = DB::transaction(function () use ($data, $request) {
            $paymentIn = PaymentIn::create([
                'company_id'          => $data['company_id'],
                'receipt_no'          => $data['receipt_no'],
                'receipt_date'        => $data['receipt_date'],
                'party_id'            => $data['party_id'],
                'total_amount'        => $data['total_amount'],
                'description'         => $data['description'] ?? null,
                'created_by_user_id'  => $request->user()->id,
            ]);

            foreach ($data['lines'] as $line) {
                PaymentInLine::create([
                    'payment_in_id'      => $paymentIn->id,
                    'payment_account_id' => $line['payment_account_id'],
                    'amount'             => $line['amount'],
                    'reference_no'       => $line['reference_no'] ?? null,
                ]);
            }

            return $paymentIn->load('lines');
        });

        return response()->json([
            'success'    => true,
            'message'    => 'Payment recorded successfully',
            'payment_in' => $result,
        ], 201);
    }

    /** PUT /api/payment-ins/{id} */
    public function update(Request $request, int $id)
    {
        $paymentIn = PaymentIn::findOrFail($id);

        if (!$this->hasAccess($request, $paymentIn->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $data = $request->validate([
            'receipt_date' => 'sometimes|date',
            'description'  => 'nullable|string',
            'total_amount' => 'sometimes|numeric',
        ]);

        $paymentIn->update($data);

        return response()->json([
            'success'    => true,
            'message'    => 'Payment updated successfully',
            'payment_in' => $paymentIn,
        ]);
    }

    /** DELETE /api/payment-ins/{id} */
    public function destroy(Request $request, int $id)
    {
        $paymentIn = PaymentIn::findOrFail($id);

        if (!$this->hasAccess($request, $paymentIn->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        DB::transaction(function () use ($paymentIn) {
            $paymentIn->lines()->delete();
            $paymentIn->delete();
        });

        return response()->json(['success' => true, 'message' => 'Payment deleted successfully']);
    }
}
