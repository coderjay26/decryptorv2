import 'dart:convert';
import 'dart:html' as html;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Model representing an active studio operator session
class AuthSession {
  final String username;
  final String token;
  final DateTime loginTime;
  final DateTime expiresAt;
  final bool rememberMe;

  AuthSession({
    required this.username,
    required this.token,
    required this.loginTime,
    required this.expiresAt,
    required this.rememberMe,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remainingTime {
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'token': token,
        'loginTime': loginTime.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'rememberMe': rememberMe,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        username: json['username'] as String? ?? 'Operator',
        token: json['token'] as String? ?? '',
        loginTime: DateTime.fromMillisecondsSinceEpoch(
            json['loginTime'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
            json['expiresAt'] as int? ?? DateTime.now().millisecondsSinceEpoch),
        rememberMe: json['rememberMe'] as bool? ?? false,
      );
}

/// Authentication and session storage service for Decryptor Studio
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _sessionKey = 'fdc_studio_session_v1';
  static const Duration _sessionDurationDefault = Duration(hours: 4);
  static const Duration _sessionDurationRememberMe = Duration(hours: 24);

  // Accepted studio credentials:
  // Default Operator: admin / ravamate@2025_secure_studio
  // Backup Operator: operator / ravamate@2025
  static final Map<String, String> _authorizedCredentials = {
    'admin': 'ravamate@2025_secure_studio',
    'operator': 'ravamate@2025',
    'fdc_admin': 'ravamate@2025_secure_32bit_key!!',
  };

  final ValueNotifier<AuthSession?> sessionNotifier =
      ValueNotifier<AuthSession?>(null);

  AuthSession? get currentSession => sessionNotifier.value;
  bool get isAuthenticated =>
      currentSession != null && !currentSession!.isExpired;

  /// Check storage on startup and restore valid session if present
  void initSession() {
    try {
      // 1. Try sessionStorage first (active tab)
      String? raw = html.window.sessionStorage[_sessionKey];

      // 2. If empty, check localStorage (persisted with "Remember Me")
      raw ??= html.window.localStorage[_sessionKey];

      if (raw != null && raw.isNotEmpty) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        final session = AuthSession.fromJson(decoded);

        if (!session.isExpired) {
          sessionNotifier.value = session;
          return;
        } else {
          // Expired session -> clear
          logout();
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to restore session: $e');
      }
      logout();
    }
    sessionNotifier.value = null;
  }

  /// Validate credentials and establish new session
  bool login({
    required String username,
    required String passkey,
    bool rememberMe = false,
  }) {
    final cleanUser = username.trim().toLowerCase();
    final cleanKey = passkey.trim();

    // Check credentials match
    final expectedPasskey = _authorizedCredentials[cleanUser];
    final isValid = expectedPasskey != null && expectedPasskey == cleanKey;

    if (!isValid) {
      return false;
    }

    // Generate SHA-256 session token
    final now = DateTime.now();
    final duration =
        rememberMe ? _sessionDurationRememberMe : _sessionDurationDefault;
    final expiresAt = now.add(duration);

    final rawTokenSeed = '$cleanUser-${now.millisecondsSinceEpoch}-$cleanKey';
    final token = sha256.convert(utf8.encode(rawTokenSeed)).toString();

    final session = AuthSession(
      username: username.trim(),
      token: token,
      loginTime: now,
      expiresAt: expiresAt,
      rememberMe: rememberMe,
    );

    try {
      final jsonStr = json.encode(session.toJson());
      // Write to sessionStorage for tab-level security
      html.window.sessionStorage[_sessionKey] = jsonStr;

      if (rememberMe) {
        // Persist in localStorage across browser restarts
        html.window.localStorage[_sessionKey] = jsonStr;
      } else {
        html.window.localStorage.remove(_sessionKey);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to write session: $e');
      }
    }

    sessionNotifier.value = session;
    return true;
  }

  /// Terminate the active session and wipe browser storage
  void logout() {
    try {
      html.window.sessionStorage.remove(_sessionKey);
      html.window.localStorage.remove(_sessionKey);
    } catch (_) {}
    sessionNotifier.value = null;
  }

  /// Extend session expiry timestamp on operator interaction
  void refreshActivity() {
    final current = currentSession;
    if (current == null || current.isExpired) return;

    final now = DateTime.now();
    final remaining = current.expiresAt.difference(now);

    // Refresh if less than half duration remains
    if (remaining.inMinutes < 60) {
      final duration = current.rememberMe
          ? _sessionDurationRememberMe
          : _sessionDurationDefault;
      final updated = AuthSession(
        username: current.username,
        token: current.token,
        loginTime: current.loginTime,
        expiresAt: now.add(duration),
        rememberMe: current.rememberMe,
      );

      try {
        final jsonStr = json.encode(updated.toJson());
        html.window.sessionStorage[_sessionKey] = jsonStr;
        if (current.rememberMe) {
          html.window.localStorage[_sessionKey] = jsonStr;
        }
      } catch (_) {}

      sessionNotifier.value = updated;
    }
  }
}
