<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Invoice;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class AttachmentController extends Controller
{
    public function uploadInvoiceAttachment(Request $request)
    {
        $data = $request->validate([
            'company_id' => 'required|integer',
            'invoice_id' => 'required|integer',
            'file' => 'required|file|mimes:jpg,jpeg,png,webp|max:5120',
        ]);

        $hasAccess = $request->user()->companies()
            ->where('companies.id', $data['company_id'])
            ->exists();

        if (!$hasAccess) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this company',
            ], 403);
        }

        $invoice = Invoice::where('company_id', $data['company_id'])
            ->where('id', $data['invoice_id'])
            ->first();

        if (!$invoice) {
            return response()->json([
                'success' => false,
                'message' => 'Invoice not found',
            ], 404);
        }

        $file = $request->file('file');
        $hash = hash_file('sha256', $file->getRealPath());
        $extension = strtolower($file->getClientOriginalExtension() ?: 'jpg');
        $safeName = Str::lower($hash . '.' . $extension);
        $dir = 'companies/' . $data['company_id'] . '/invoices/' . $data['invoice_id'];
        $storagePath = $dir . '/' . $safeName;

        if (!Storage::disk('public')->exists($storagePath)) {
            Storage::disk('public')->putFileAs($dir, $file, $safeName);
        }

        $publicUrl = Storage::disk('public')->url($storagePath);
        $invoice->attachment_path = $publicUrl;
        $invoice->save();

        return response()->json([
            'success' => true,
            'attachment_path' => $publicUrl,
            'attachment_storage_path' => $storagePath,
            'checksum_sha256' => $hash,
            'size' => $file->getSize(),
            'mime' => $file->getMimeType(),
        ]);
    }

    public function downloadInvoiceAttachment(Request $request, int $invoiceId)
    {
        $invoice = Invoice::find($invoiceId);
        if (!$invoice) {
            return response()->json([
                'success' => false,
                'message' => 'Invoice not found',
            ], 404);
        }

        $hasAccess = $request->user()->companies()
            ->where('companies.id', $invoice->company_id)
            ->exists();

        if (!$hasAccess) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this company',
            ], 403);
        }

        if (!$invoice->attachment_path) {
            return response()->json([
                'success' => false,
                'message' => 'No attachment found for this invoice',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'attachment_path' => $invoice->attachment_path,
        ]);
    }
}
