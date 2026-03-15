<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\PersonalAccessToken;

class AuthController extends Controller
{
    private const ACCESS_TOKEN_LIFETIME_HOURS = 8;
    private const REFRESH_TOKEN_LIFETIME_DAYS = 30;

    /**
     * Issue an access/refresh token pair for a device.
     *
     * @return array{access_token: string, refresh_token: string, access_token_expires_at: string, refresh_token_expires_at: string}
     */
    private function issueTokenPair(User $user, ?string $deviceId = null): array
    {
        $tokenBase = $this->normalizeTokenBase($deviceId);
        $this->revokeTokenPair($user, $tokenBase);

        $accessExpiresAt = now()->addHours(self::ACCESS_TOKEN_LIFETIME_HOURS);
        $refreshExpiresAt = now()->addDays(self::REFRESH_TOKEN_LIFETIME_DAYS);

        $accessToken = $user->createToken(
            $tokenBase . ':access',
            ['access'],
            $accessExpiresAt,
        )->plainTextToken;

        $refreshToken = $user->createToken(
            $tokenBase . ':refresh',
            ['refresh'],
            $refreshExpiresAt,
        )->plainTextToken;

        return [
            'access_token' => $accessToken,
            'refresh_token' => $refreshToken,
            'access_token_expires_at' => $accessExpiresAt->toIso8601String(),
            'refresh_token_expires_at' => $refreshExpiresAt->toIso8601String(),
        ];
    }

    private function normalizeTokenBase(?string $deviceId = null): string
    {
        $trimmed = trim((string) $deviceId);

        return $trimmed !== '' ? $trimmed : 'auth-token';
    }

    private function tokenBaseFromName(?string $tokenName): string
    {
        $name = (string) $tokenName;
        if (str_ends_with($name, ':access')) {
            return substr($name, 0, -7);
        }

        if (str_ends_with($name, ':refresh')) {
            return substr($name, 0, -8);
        }

        return $this->normalizeTokenBase($name);
    }

    private function revokeTokenPair(User $user, ?string $deviceId = null): void
    {
        $tokenBase = $this->normalizeTokenBase($deviceId);
        $user->tokens()->whereIn('name', [
            $tokenBase,
            $tokenBase . ':access',
            $tokenBase . ':refresh',
        ])->delete();
    }

    private function resolveUserFromBearerToken(Request $request): ?User
    {
        $token = $request->bearerToken();
        if (!$token) {
            return null;
        }

        $tokenModel = PersonalAccessToken::findToken($token);
        $tokenUser = $tokenModel?->tokenable;

        return $tokenUser instanceof User ? $tokenUser : null;
    }

    private function tokenHasAbility(PersonalAccessToken $token, string $ability): bool
    {
        $abilities = $token->abilities ?? [];

        return in_array('*', $abilities, true) || in_array($ability, $abilities, true);
    }

    private function tokenIsExpired(PersonalAccessToken $token): bool
    {
        return $token->expires_at !== null && $token->expires_at->isPast();
    }

    /**
     * Register a new user
     */
    public function register(Request $request)
    {
        $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|unique:users',
            'password' => 'required|string|min:8|confirmed',
            'role' => 'nullable|in:admin,user',
            'device_id' => 'nullable|string|max:255',
        ]);

        $requestedRole = strtolower((string) $request->input('role', 'user'));
        $adminExists = User::where('role', 'admin')->exists();
        $actingUser = $request->user() ?? $this->resolveUserFromBearerToken($request);

        if (!$adminExists && $requestedRole !== 'admin') {
            return response()->json([
                'success' => false,
                'message' => 'The first registered account must be an admin.',
            ], 422);
        }

        if ($adminExists) {
            if (!$actingUser) {
                return response()->json([
                    'success' => false,
                    'message' => 'Registration is closed. Contact your admin.',
                ], 403);
            }

            if ($actingUser->role !== 'admin') {
                return response()->json([
                    'success' => false,
                    'message' => 'Only admin users can create users.',
                ], 403);
            }
        }

        $tenantAdminId = null;
        if ($actingUser && $actingUser->role === 'admin') {
            $tenantAdminId = $actingUser->subscriber_id ?: $actingUser->id;
        }

        $user = User::create([
            'email' => $request->email,
            'full_name' => $request->name,
            'role' => $requestedRole,
            'subscriber_id' => $tenantAdminId,
            'password' => Hash::make($request->password),
            'is_active' => true,
        ]);

        if (!$adminExists && $user->role === 'admin') {
            $user->subscriber_id = $user->id;
            $user->save();
        }

        $tokens = $this->issueTokenPair($user, $request->input('device_id'));

        return response()->json([
            'success' => true,
            'message' => 'User registered successfully',
            'user' => [
                'id' => $user->id,
                'email' => $user->email,
                'full_name' => $user->full_name,
                'role' => $user->role,
                'subscriber_id' => $user->subscriber_id,
            ],
            'token' => $tokens['access_token'],
            'refresh_token' => $tokens['refresh_token'],
            'token_expires_at' => $tokens['access_token_expires_at'],
            'refresh_token_expires_at' => $tokens['refresh_token_expires_at'],
        ], 201);
    }

    /**
     * Login user
     */
    public function login(Request $request)
    {
        $request->validate([
            'email' => 'required|email',
            'password' => 'required',
            'device_id' => 'nullable|string',
        ]);

        $user = User::where('email', $request->email)->first();

        if (!$user || !Hash::check($request->password, $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['The provided credentials are incorrect.'],
            ]);
        }

        if (!$user->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Your account has been deactivated.'],
            ]);
        }

        $tokens = $this->issueTokenPair($user, $request->input('device_id'));

        return response()->json([
            'success' => true,
            'message' => 'Login successful',
            'user' => [
                'id' => $user->id,
                'email' => $user->email,
                'full_name' => $user->full_name,
                'role' => $user->role,
                'subscriber_id' => $user->subscriber_id,
                'companies' => $user->companies,
            ],
            'token' => $tokens['access_token'],
            'refresh_token' => $tokens['refresh_token'],
            'token_expires_at' => $tokens['access_token_expires_at'],
            'refresh_token_expires_at' => $tokens['refresh_token_expires_at'],
        ]);
    }

    /**
     * Refresh an expired access token using a refresh token.
     */
    public function refresh(Request $request)
    {
        $request->validate([
            'refresh_token' => 'required|string',
            'device_id' => 'nullable|string|max:255',
        ]);

        $refreshToken = PersonalAccessToken::findToken($request->input('refresh_token'));
        if (!$refreshToken || !$this->tokenHasAbility($refreshToken, 'refresh') || $this->tokenIsExpired($refreshToken)) {
            if ($refreshToken) {
                $refreshToken->delete();
            }

            return response()->json([
                'success' => false,
                'message' => 'Refresh token is invalid or expired.',
            ], 401);
        }

        $user = $refreshToken->tokenable;
        if (!$user instanceof User) {
            $refreshToken->delete();

            return response()->json([
                'success' => false,
                'message' => 'Refresh token is invalid.',
            ], 401);
        }

        if (!$user->is_active) {
            $this->revokeTokenPair($user, $this->tokenBaseFromName($refreshToken->name));

            return response()->json([
                'success' => false,
                'message' => 'Your account has been deactivated.',
            ], 403);
        }

        $tokenBase = $this->tokenBaseFromName($refreshToken->name);
        $requestedDeviceId = trim((string) $request->input('device_id', ''));
        if ($requestedDeviceId !== '' && $requestedDeviceId !== $tokenBase) {
            return response()->json([
                'success' => false,
                'message' => 'Refresh token does not belong to this device.',
            ], 401);
        }

        $refreshToken->delete();
        $tokens = $this->issueTokenPair($user, $tokenBase);

        return response()->json([
            'success' => true,
            'message' => 'Token refreshed successfully',
            'user' => [
                'id' => $user->id,
                'email' => $user->email,
                'full_name' => $user->full_name,
                'role' => $user->role,
                'subscriber_id' => $user->subscriber_id,
                'companies' => $user->companies,
            ],
            'token' => $tokens['access_token'],
            'refresh_token' => $tokens['refresh_token'],
            'token_expires_at' => $tokens['access_token_expires_at'],
            'refresh_token_expires_at' => $tokens['refresh_token_expires_at'],
        ]);
    }

    /**
     * Logout user
     */
    public function logout(Request $request)
    {
        $user = $request->user();
        $currentToken = $user?->currentAccessToken();

        if ($user && $currentToken) {
            $tokenBase = $this->tokenBaseFromName($currentToken->name);
            $user->tokens()->whereIn('name', [
                $currentToken->name,
                $tokenBase,
                $tokenBase . ':access',
                $tokenBase . ':refresh',
            ])->delete();
        }

        return response()->json([
            'success' => true,
            'message' => 'Logged out successfully',
        ]);
    }

    /**
     * Get authenticated user
     */
    public function user(Request $request)
    {
        return response()->json([
            'success' => true,
            'user' => [
                'id' => $request->user()->id,
                'email' => $request->user()->email,
                'full_name' => $request->user()->full_name,
                'role' => $request->user()->role,
                'subscriber_id' => $request->user()->subscriber_id,
                'companies' => $request->user()->companies,
            ],
        ]);
    }

    /**
     * Change authenticated user's password or allow admin to reset a managed user's password.
     */
    public function changePassword(Request $request)
    {
        $actingUser = $request->user();
        if (!$actingUser) {
            return response()->json([
                'success' => false,
                'message' => 'Unauthenticated.',
            ], 401);
        }

        $request->validate([
            'target_user_id' => 'nullable|integer|exists:users,id',
            'current_password' => 'nullable|string',
            'password' => 'required|string|min:8|confirmed',
        ]);

        $targetUserId = (int) ($request->input('target_user_id') ?? $actingUser->id);
        $changingOwnPassword = $targetUserId === (int) $actingUser->id;

        if (!$changingOwnPassword && $actingUser->role !== 'admin') {
            return response()->json([
                'success' => false,
                'message' => 'Only admin users can reset another user password.',
            ], 403);
        }

        $targetUser = User::find($targetUserId);
        if (!$targetUser) {
            return response()->json([
                'success' => false,
                'message' => 'Target user not found.',
            ], 404);
        }

        if ($changingOwnPassword) {
            $currentPassword = (string) $request->input('current_password', '');
            if ($currentPassword === '' || !Hash::check($currentPassword, $actingUser->password)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Current password is incorrect.',
                ], 422);
            }
        } else {
            $actingTenantId = $actingUser->subscriber_id ?: $actingUser->id;
            $targetTenantId = $targetUser->subscriber_id ?: $targetUser->id;
            if ((int) $actingTenantId !== (int) $targetTenantId) {
                return response()->json([
                    'success' => false,
                    'message' => 'You can only reset password for users in your tenant.',
                ], 403);
            }
        }

        $targetUser->password = Hash::make($request->password);
        $targetUser->save();

        return response()->json([
            'success' => true,
            'message' => $changingOwnPassword
                ? 'Password updated successfully.'
                : 'User password reset successfully.',
        ]);
    }
}
