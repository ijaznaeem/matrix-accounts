<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\SyncController;
use App\Http\Controllers\Api\CompanyController;
use App\Http\Controllers\Api\PartyController;
use App\Http\Controllers\Api\ProductController;
use App\Http\Controllers\Api\InvoiceController;
use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\PaymentAccountController;
use App\Http\Controllers\Api\PaymentInController;
use App\Http\Controllers\Api\PaymentOutController;
use App\Http\Controllers\Api\AttachmentController;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
*/

// Health check
Route::get('/health', function () {
    return response()->json([
        'status'    => 'ok',
        'timestamp' => now()->toIso8601String(),
        'service'   => 'Veyo Sync API',
    ]);
});

// Public auth routes
Route::post('/auth/register', [AuthController::class, 'register']);
Route::post('/auth/login',    [AuthController::class, 'login']);
Route::post('/auth/refresh',  [AuthController::class, 'refresh']);

// Protected routes (require Sanctum bearer token)
Route::middleware('auth:sanctum')->group(function () {

    // ── Auth ──────────────────────────────────────────
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/auth/user',    [AuthController::class, 'user']);
    Route::post('/auth/change-password', [AuthController::class, 'changePassword']);

    // ── Companies ─────────────────────────────────────
    Route::get('/companies',  [CompanyController::class, 'index']);
    Route::post('/companies', [CompanyController::class, 'store']);

    // ── Sync ──────────────────────────────────────────
    Route::prefix('sync')->group(function () {
        Route::post('/pull',   [SyncController::class, 'pull']);
        Route::post('/push',   [SyncController::class, 'push']);
        Route::get('/status',  [SyncController::class, 'status']);
    });

    // ── Parties ───────────────────────────────────────
    Route::get('/parties',       [PartyController::class, 'index']);
    Route::post('/parties',      [PartyController::class, 'store']);
    Route::put('/parties/{id}',  [PartyController::class, 'update']);
    Route::delete('/parties/{id}', [PartyController::class, 'destroy']);

    // ── Products ──────────────────────────────────────
    Route::get('/products',        [ProductController::class, 'index']);
    Route::post('/products',       [ProductController::class, 'store']);
    Route::put('/products/{id}',   [ProductController::class, 'update']);
    Route::delete('/products/{id}',[ProductController::class, 'destroy']);

    // ── Invoices ──────────────────────────────────────
    Route::get('/invoices',        [InvoiceController::class, 'index']);
    Route::post('/invoices',       [InvoiceController::class, 'store']);
    Route::put('/invoices/{id}',   [InvoiceController::class, 'update']);
    Route::delete('/invoices/{id}',[InvoiceController::class, 'destroy']);

    // ── Attachments ───────────────────────────────────
    Route::post('/attachments/invoice/upload', [AttachmentController::class, 'uploadInvoiceAttachment']);
    Route::get('/attachments/invoice/{invoiceId}', [AttachmentController::class, 'downloadInvoiceAttachment']);

    // ── Accounts & ledger ─────────────────────────────
    Route::get('/accounts',              [AccountController::class, 'index']);
    Route::get('/accounts/balance',      [AccountController::class, 'partyBalance']);
    Route::get('/account-transactions',  [AccountController::class, 'transactions']);

    // ── Payment accounts ──────────────────────────────
    Route::get('/payment-accounts',       [PaymentAccountController::class, 'index']);
    Route::post('/payment-accounts',      [PaymentAccountController::class, 'store']);
    Route::put('/payment-accounts/{id}',  [PaymentAccountController::class, 'update']);

    // ── Payments In ───────────────────────────────────
    Route::get('/payment-ins',        [PaymentInController::class, 'index']);
    Route::post('/payment-ins',       [PaymentInController::class, 'store']);
    Route::put('/payment-ins/{id}',   [PaymentInController::class, 'update']);
    Route::delete('/payment-ins/{id}',[PaymentInController::class, 'destroy']);

    // ── Payments Out ──────────────────────────────────
    Route::get('/payment-outs',        [PaymentOutController::class, 'index']);
    Route::post('/payment-outs',       [PaymentOutController::class, 'store']);
    Route::put('/payment-outs/{id}',   [PaymentOutController::class, 'update']);
    Route::delete('/payment-outs/{id}',[PaymentOutController::class, 'destroy']);
});
