<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Invoice;
use App\Models\Transaction;
use App\Models\TransactionLine;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class InvoiceController extends Controller
{
    private function hasAccess(Request $request, int $companyId): bool
    {
        return $request->user()->companies()
            ->where('companies.id', $companyId)
            ->exists();
    }

    /** GET /api/invoices?company_id=&invoice_type=sale|purchase&party_id= */
    public function index(Request $request)
    {
        $request->validate([
            'company_id'   => 'required|integer',
            'invoice_type' => 'nullable|in:sale,purchase',
            'party_id'     => 'nullable|integer',
        ]);

        if (!$this->hasAccess($request, $request->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $query = Invoice::with('transaction.lines')
            ->where('company_id', $request->company_id);

        if ($request->invoice_type) {
            $query->where('invoice_type', $request->invoice_type);
        }
        if ($request->party_id) {
            $query->where('party_id', $request->party_id);
        }

        $invoices = $query->orderBy('invoice_date', 'desc')->get();

        return response()->json(['success' => true, 'invoices' => $invoices]);
    }

    /**
     * POST /api/invoices
     * Creates a Transaction + TransactionLines + Invoice atomically.
     */
    public function store(Request $request)
    {
        $data = $request->validate([
            'company_id'        => 'required|integer',
            'invoice_type'      => 'required|in:sale,purchase',
            'party_id'          => 'required|integer',
            'invoice_date'      => 'required|date',
            'due_date'          => 'nullable|date',
            'invoice_number'    => [
                'nullable',
                'string',
                'max:100',
                Rule::unique('invoices', 'invoice_number')
                    ->where(fn ($query) => $query->where('company_id', (int) $request->input('company_id'))),
            ],
            'reference_no'      => 'required|string|max:100',
            'previous_balance'  => 'nullable|numeric',
            'paid_amount'       => 'nullable|numeric',
            'remaining_balance' => 'nullable|numeric',
            'grand_total'       => 'required|numeric',
            'status'            => 'nullable|string|max:50',
            'notes'             => 'nullable|string',
            'attachment_path'   => 'nullable|string|max:1024',
            'lines'             => 'required|array|min:1',
            'lines.*.product_id' => 'nullable|integer',
            'lines.*.description' => 'nullable|string',
            'lines.*.quantity'   => 'required|numeric',
            'lines.*.unit_price' => 'required|numeric',
            'lines.*.line_amount' => 'required|numeric',
        ]);

        if (!$this->hasAccess($request, $data['company_id'])) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $result = DB::transaction(function () use ($data, $request) {
            $type = $data['invoice_type'] === 'sale' ? 'sale' : 'purchase';

            $transaction = Transaction::create([
                'company_id'          => $data['company_id'],
                'type'                => $type,
                'date'                => $data['invoice_date'],
                'reference_no'        => $data['reference_no'],
                'party_id'            => $data['party_id'],
                'total_amount'        => $data['grand_total'],
                'is_posted'           => true,
                'created_by_user_id'  => $request->user()->id,
            ]);

            foreach ($data['lines'] as $line) {
                TransactionLine::create([
                    'transaction_id' => $transaction->id,
                    'product_id'     => $line['product_id'] ?? null,
                    'description'    => $line['description'] ?? null,
                    'quantity'       => $line['quantity'],
                    'unit_price'     => $line['unit_price'],
                    'line_amount'    => $line['line_amount'],
                ]);
            }

            $invoice = Invoice::create([
                'company_id'        => $data['company_id'],
                'transaction_id'    => $transaction->id,
                'invoice_type'      => $data['invoice_type'],
                'party_id'          => $data['party_id'],
                'invoice_date'      => $data['invoice_date'],
                'due_date'          => $data['due_date'] ?? null,
                'grand_total'       => $data['grand_total'],
                'status'            => $data['status'] ?? 'Pending',
                'previous_balance'  => $data['previous_balance'] ?? 0,
                'paid_amount'       => $data['paid_amount'] ?? 0,
                'remaining_balance' => $data['remaining_balance'] ?? 0,
                'invoice_number'    => $data['invoice_number'] ?? null,
                'notes'             => $data['notes'] ?? null,
                'attachment_path'   => $data['attachment_path'] ?? null,
            ]);

            return $invoice->load('transaction.lines');
        });

        return response()->json([
            'success' => true,
            'message' => 'Invoice created successfully',
            'invoice' => $result,
        ], 201);
    }

    /** PUT /api/invoices/{id} */
    public function update(Request $request, int $id)
    {
        $invoice = Invoice::findOrFail($id);

        if (!$this->hasAccess($request, $invoice->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        $data = $request->validate([
            'invoice_date'      => 'sometimes|date',
            'due_date'          => 'nullable|date',
            'grand_total'       => 'sometimes|numeric',
            'status'            => 'nullable|string|max:50',
            'previous_balance'  => 'nullable|numeric',
            'paid_amount'       => 'nullable|numeric',
            'remaining_balance' => 'nullable|numeric',
            'invoice_number'    => [
                'nullable',
                'string',
                'max:100',
                Rule::unique('invoices', 'invoice_number')
                    ->where(fn ($query) => $query->where('company_id', $invoice->company_id))
                    ->ignore($invoice->id),
            ],
            'notes'             => 'nullable|string',
            'attachment_path'   => 'nullable|string|max:1024',
        ]);

        $invoice->update($data);

        return response()->json([
            'success' => true,
            'message' => 'Invoice updated successfully',
            'invoice' => $invoice,
        ]);
    }

    /** DELETE /api/invoices/{id} */
    public function destroy(Request $request, int $id)
    {
        $invoice = Invoice::findOrFail($id);

        if (!$this->hasAccess($request, $invoice->company_id)) {
            return response()->json(['success' => false, 'message' => 'Access denied'], 403);
        }

        DB::transaction(function () use ($invoice) {
            $invoice->transaction?->lines()->delete();
            $invoice->transaction?->delete();
            $invoice->delete();
        });

        return response()->json(['success' => true, 'message' => 'Invoice deleted successfully']);
    }
}
