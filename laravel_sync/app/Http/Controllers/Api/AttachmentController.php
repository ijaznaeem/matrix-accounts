<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Invoice;
use App\Models\PaymentIn;
use App\Models\PaymentOut;
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

        $publicUrl = asset('storage/' . $storagePath);
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

    public function uploadPaymentInAttachment(Request $request)
    {
        $data = $request->validate([
            'company_id' => 'required|integer',
            'payment_in_id' => 'required|integer',
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

        $paymentIn = PaymentIn::where('company_id', $data['company_id'])
            ->where('id', $data['payment_in_id'])
            ->first();

        if (!$paymentIn) {
            return response()->json([
                'success' => false,
                'message' => 'Payment In not found',
            ], 404);
        }

        $file = $request->file('file');
        $hash = hash_file('sha256', $file->getRealPath());
        $extension = strtolower($file->getClientOriginalExtension() ?: 'jpg');
        $safeName = Str::lower($hash . '.' . $extension);
        $dir = 'companies/' . $data['company_id'] . '/payment-ins/' . $data['payment_in_id'];
        $storagePath = $dir . '/' . $safeName;

        if (!Storage::disk('public')->exists($storagePath)) {
            Storage::disk('public')->putFileAs($dir, $file, $safeName);
        }

        $publicUrl = asset('storage/' . $storagePath);
        $paymentIn->attachment_path = $publicUrl;
        $paymentIn->save();

        return response()->json([
            'success' => true,
            'attachment_path' => $publicUrl,
            'attachment_storage_path' => $storagePath,
            'checksum_sha256' => $hash,
            'size' => $file->getSize(),
            'mime' => $file->getMimeType(),
        ]);
    }

    public function uploadPaymentOutAttachment(Request $request)
    {
        $data = $request->validate([
            'company_id' => 'required|integer',
            'payment_out_id' => 'required|integer',
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

        $paymentOut = PaymentOut::where('company_id', $data['company_id'])
            ->where('id', $data['payment_out_id'])
            ->first();

        if (!$paymentOut) {
            return response()->json([
                'success' => false,
                'message' => 'Payment Out not found',
            ], 404);
        }

        $file = $request->file('file');
        $hash = hash_file('sha256', $file->getRealPath());
        $extension = strtolower($file->getClientOriginalExtension() ?: 'jpg');
        $safeName = Str::lower($hash . '.' . $extension);
        $dir = 'companies/' . $data['company_id'] . '/payment-outs/' . $data['payment_out_id'];
        $storagePath = $dir . '/' . $safeName;

        if (!Storage::disk('public')->exists($storagePath)) {
            Storage::disk('public')->putFileAs($dir, $file, $safeName);
        }

        $publicUrl = asset('storage/' . $storagePath);
        $paymentOut->attachment_path = $publicUrl;
        $paymentOut->save();

        return response()->json([
            'success' => true,
            'attachment_path' => $publicUrl,
            'attachment_storage_path' => $storagePath,
            'checksum_sha256' => $hash,
            'size' => $file->getSize(),
            'mime' => $file->getMimeType(),
        ]);
    }

    public function downloadPaymentInAttachment(Request $request, int $paymentInId)
    {
        $paymentIn = PaymentIn::find($paymentInId);
        if (!$paymentIn) {
            return response()->json([
                'success' => false,
                'message' => 'Payment In not found',
            ], 404);
        }

        $hasAccess = $request->user()->companies()
            ->where('companies.id', $paymentIn->company_id)
            ->exists();

        if (!$hasAccess) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this company',
            ], 403);
        }

        if (!$paymentIn->attachment_path) {
            return response()->json([
                'success' => false,
                'message' => 'No attachment found for this payment in',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'attachment_path' => $paymentIn->attachment_path,
        ]);
    }

    public function downloadPaymentOutAttachment(Request $request, int $paymentOutId)
    {
        $paymentOut = PaymentOut::find($paymentOutId);
        if (!$paymentOut) {
            return response()->json([
                'success' => false,
                'message' => 'Payment Out not found',
            ], 404);
        }

        $hasAccess = $request->user()->companies()
            ->where('companies.id', $paymentOut->company_id)
            ->exists();

        if (!$hasAccess) {
            return response()->json([
                'success' => false,
                'message' => 'You do not have access to this company',
            ], 403);
        }

        if (!$paymentOut->attachment_path) {
            return response()->json([
                'success' => false,
                'message' => 'No attachment found for this payment out',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'attachment_path' => $paymentOut->attachment_path,
        ]);
    }
}
