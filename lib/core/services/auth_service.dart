import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/user_model.dart';
import 'api_client.dart';

/// Service for managing user authentication state persistence
class AuthService {
  static const String _keyUserId = 'user_id';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserFullName = 'user_full_name';
  static const String _keySelectedCompanyId = 'selected_company_id';
  static const String _keySelectedCompanyName = 'selected_company_name';
  static const String _keyAuthToken = 'auth_token';
  static const String _keyRefreshToken = 'refresh_token';

  final SharedPreferences _prefs;

  AuthService(this._prefs);

  /// Access token is the source of truth for local authenticated session state.
  String? get authToken => _prefs.getString(_keyAuthToken);

  /// Long-lived refresh token used to rotate expired access tokens.
  String? get refreshToken => _prefs.getString(_keyRefreshToken);

  /// Check if a user currently has a stored auth token.
  bool get isLoggedIn => authToken?.isNotEmpty ?? false;

  /// Get the stored user ID
  int? get userId {
    final id = _prefs.getInt(_keyUserId);
    return id == 0 ? null : id;
  }

  /// Get the stored user email
  String? get userEmail => _prefs.getString(_keyUserEmail);

  /// Get the stored user full name
  String? get userFullName => _prefs.getString(_keyUserFullName);

  /// Get the stored company ID
  int? get selectedCompanyId {
    final id = _prefs.getInt(_keySelectedCompanyId);
    return id == 0 ? null : id;
  }

  /// Get the stored company name
  String? get selectedCompanyName => _prefs.getString(_keySelectedCompanyName);

  /// Check if a company has been selected
  bool get hasSelectedCompany => selectedCompanyId != null;

  /// Save authenticated session using the issued access token and cached user profile.
  Future<bool> saveAuthenticatedSession({
    required String token,
    required int userId,
    required String email,
    required String fullName,
    String? refreshToken,
  }) async {
    try {
      final previousUserId = _prefs.getInt(_keyUserId);

      await _prefs.setString(_keyAuthToken, token);
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _prefs.setString(_keyRefreshToken, refreshToken);
      }
      await _prefs.setInt(_keyUserId, userId);
      await _prefs.setString(_keyUserEmail, email);
      await _prefs.setString(_keyUserFullName, fullName);

      if (previousUserId != null && previousUserId != userId) {
        await clearSelectedCompany();
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Backward-compatible wrapper while callers are migrated.
  Future<bool> saveLoginState({
    required int userId,
    required String email,
    required String fullName,
    String? refreshToken,
  }) async {
    final token = authToken;
    if (token == null || token.isEmpty) {
      return false;
    }

    return saveAuthenticatedSession(
      token: token,
      userId: userId,
      email: email,
      fullName: fullName,
      refreshToken: refreshToken,
    );
  }

  /// Clear all user login state
  Future<bool> logout({ApiClient? apiClient}) async {
    try {
      if (apiClient != null && (authToken?.isNotEmpty ?? false)) {
        try {
          await apiClient.post('/api/auth/logout', {});
        } catch (_) {
          // Local logout still proceeds if the remote token is already invalid.
        }
      }

      await _prefs.remove(_keyUserId);
      await _prefs.remove(_keyUserEmail);
      await _prefs.remove(_keyUserFullName);
      await _prefs.remove(_keySelectedCompanyId);
      await _prefs.remove(_keySelectedCompanyName);
      await _prefs.remove(_keyAuthToken);
      await _prefs.remove(_keyRefreshToken);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear only authentication/session state while preserving app-level settings.
  Future<bool> clearAuthSession({bool clearSelectedCompany = false}) async {
    try {
      await _prefs.remove(_keyAuthToken);
      await _prefs.remove(_keyRefreshToken);
      await _prefs.remove(_keyUserId);
      await _prefs.remove(_keyUserEmail);
      await _prefs.remove(_keyUserFullName);

      if (clearSelectedCompany) {
        await _prefs.remove(_keySelectedCompanyId);
        await _prefs.remove(_keySelectedCompanyName);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Save selected company
  Future<bool> saveSelectedCompany({
    required int companyId,
    required String companyName,
  }) async {
    try {
      await _prefs.setInt(_keySelectedCompanyId, companyId);
      await _prefs.setString(_keySelectedCompanyName, companyName);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear selected company
  Future<bool> clearSelectedCompany() async {
    try {
      await _prefs.remove(_keySelectedCompanyId);
      await _prefs.remove(_keySelectedCompanyName);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get a User object from persisted state (if logged in)
  User? getPersistedUser() {
    if (!isLoggedIn) return null;

    final id = userId;
    final email = userEmail;
    final fullName = userFullName;

    if (id == null || email == null || fullName == null) {
      return null;
    }

    return User()
      ..id = id
      ..email = email
      ..fullName = fullName
      ..passwordHash = ''
      ..isActive = true;
  }

  /// Restore and validate current user from the stored auth token.
  /// On auth failure, clears the token-backed session.
  /// On network failure, falls back to cached user if available.
  Future<User?> restoreAuthenticatedUser(ApiClient apiClient) async {
    final token = authToken;
    if (token == null || token.isEmpty) return null;

    final cachedUser = getPersistedUser();

    try {
      final response = await apiClient.get('/api/auth/user');
      if (response['success'] != true || response['user'] is! Map) {
        return cachedUser;
      }

      final userData = Map<String, dynamic>.from(response['user'] as Map);
      final userId = userData['id'] as int?;
      final email = userData['email']?.toString();
      final fullName = userData['full_name']?.toString();

      if (userId == null || email == null || fullName == null) {
        return cachedUser;
      }

      await saveAuthenticatedSession(
        token: token,
        userId: userId,
        email: email,
        fullName: fullName,
        refreshToken: refreshToken,
      );

      return User()
        ..id = userId
        ..email = email
        ..fullName = fullName
        ..passwordHash = ''
        ..isActive = true;
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await clearAuthSession();
        return null;
      }
      return cachedUser;
    } catch (_) {
      return cachedUser;
    }
  }
}
