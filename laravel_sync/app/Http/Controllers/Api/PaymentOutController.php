<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PaymentOut;
use App\Models\PaymentOutLine;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PaymentOutController extends Controller
{
    private function hasAccess(Request $request, int $companyId): bool
    {
        return $request->user()->companies()
            ->where('companies.id', $companyId)
            ->exists();
    }

    /** GET /api/payment-outs?company_id=&party_id= */
    public function index(Request $request)
    {
        $request->validate([
            'company_id' => 'required|integer',
            'party_id'   => 'nullable|integer',
        ]);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $query = PaymentOut::with('lines')
            ->where('company_id', $request->company_id);

        if ($request->party_id) {
            $query->where('party_id', $request->party_id);
        }

        return response()->json([
            'success'      => true,
            'payment_outs' => $query->orderBy('voucher_date', 'desc')->get(),
        ]);
    }

    /** POST /api/payment-outs */
    public function store(Request $request)
    {
        $data = $request->validate([
            'company_id'           => 'required|integer',
            'voucher_no'           => 'required|string|max:100',
            'voucher_date'         => 'required|date',
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
            $paymentOut = PaymentOut::create([
                'company_id'          => $data['company_id'],
                'voucher_no'          => $data['voucher_no'],
                'voucher_date'        => $data['voucher_date'],
                'party_id'            => $data['party_id'],
                'total_amount'        => $data['total_amount'],
                'description'         => $data['description'] ?? null,
                'created_by_user_id'  => $request->user()->id,
            ]);

            foreach ($data['lines'] as $line) {
                PaymentOutLine::create([
                    'payment_out_id'     => $paymentOut->id,
                    'payment_account_id' => $line['payment_account_id'],
                    'amount'             => $line['amount'],
                    'reference_no'       => $line['reference_no'] ?? null,
                ]);
            }

            return $paymentOut->load('lines');
        });

        return response()->json([
            'success'     => true,
            'message'     => 'Payment recorded successfully',
            'payment_out' => $result,
        ], 201);
    }

    /** PUT /api/payment-outs/{id} */
    public function update(Request $request, int $id)
    {
        $paymentOut = PaymentOut::findOrFail($id);

        if (!$this->hasAccess($request, $paymentOut->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $data = $request->validate([
            'voucher_date' => 'sometimes|date',
            'description'  => 'nullable|string',
            'total_amount' => 'sometimes|numeric',
        ]);

        $paymentOut->update($data);

        return response()->json([
            'success'     => true,
            'message'     => 'Payment updated successfully',
            'payment_out' => $paymentOut,
        ]);
    }

    /** DELETE /api/payment-outs/{id} */
    public function destroy(Request $request, int $id)
    {
        $paymentOut = PaymentOut::findOrFail($id);

        if (!$this->hasAccess($request, $paymentOut->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        DB::transaction(function () use ($paymentOut) {
            $paymentOut->lines()->delete();
            $paymentOut->delete();
        });

        return response()->json(['success' => true, 'message' => 'Payment deleted successfully']);
    }
}
