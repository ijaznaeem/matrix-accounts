<?php

use App\Http\Controllers\Web\SuperAdminAuthController;
use App\Http\Controllers\Web\SuperAdminPanelController;
use Illuminate\Support\Facades\Route;

Route::redirect('/', '/super-admin/login');

Route::middleware('guest')->group(function () {
    Route::get('/super-admin/login', [SuperAdminAuthController::class, 'create'])
        ->name('super-admin.login');
    Route::post('/super-admin/login', [SuperAdminAuthController::class, 'store'])
        ->name('super-admin.login.store');
});

Route::middleware(['auth', 'super_admin'])->prefix('super-admin')->name('super-admin.')->group(function () {
    Route::get('/', [SuperAdminPanelController::class, 'index'])->name('dashboard');
    Route::get('/overview', [SuperAdminPanelController::class, 'overview'])->name('overview');
    Route::get('/register-client', [SuperAdminPanelController::class, 'registerClientPage'])->name('register');
    Route::get('/clients', [SuperAdminPanelController::class, 'clientsPage'])->name('clients');
    Route::get('/clients/{client}/manage', [SuperAdminPanelController::class, 'clientManagementPage'])->name('clients.manage');
    Route::get('/billing', [SuperAdminPanelController::class, 'billingPage'])->name('billing');
    Route::post('/logout', [SuperAdminAuthController::class, 'destroy'])->name('logout');

    Route::post('/clients', [SuperAdminPanelController::class, 'storeClient'])->name('clients.store');
    Route::patch('/clients/{client}', [SuperAdminPanelController::class, 'updateClient'])->name('clients.update');
    Route::delete('/clients/{client}', [SuperAdminPanelController::class, 'destroyClient'])->name('clients.destroy');
    Route::patch('/clients/{client}/status', [SuperAdminPanelController::class, 'toggleClientStatus'])->name('clients.status');
    Route::post('/clients/{client}/extend', [SuperAdminPanelController::class, 'extendSubscription'])->name('clients.extend');
    Route::post('/clients/{client}/billing', [SuperAdminPanelController::class, 'storeBillingRecord'])->name('clients.billing.store');
});
