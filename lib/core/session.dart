import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'offline_credential.dart';

/// Signed-in user and phone, as the server returned them at login.
class Session {
  Session({
    required this.serverUrl,
    required this.token,
    required this.user,
    required this.device,
    required this.abilities,
    this.issuedAt,
    this.expiresAt,
    this.needsReauth = false,
  });

  final String serverUrl;

  /// Empty when the app was opened without signal; work is kept until the next online login.
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> device;
  final List<String> abilities;
  final DateTime? issuedAt;
  final DateTime? expiresAt;

  /// The server does not accept this session (opened offline, expired or closed):
  /// the user keeps working on the phone and enters the password again to send.
  final bool needsReauth;

  int get userId => (user['id'] as num).toInt();
  String get userName => user['name'] as String? ?? '';
  String get email => user['email'] as String? ?? '';
  String get role => user['role'] as String? ?? '';
  String get deviceCode => device['code'] as String? ?? '';
  bool get canSync => token.isNotEmpty && !needsReauth;

  bool can(String ability) => abilities.contains(ability);

  /// A token older than this is swapped for a new one while there is signal.
  static const renewAfter = Duration(days: 7);

  bool shouldRenew(DateTime now) => canSync && (issuedAt == null || now.difference(issuedAt!) >= renewAfter);

  Session copyWith({String? token, List<String>? abilities, Map<String, dynamic>? user, Map<String, dynamic>? device, DateTime? issuedAt, DateTime? expiresAt, bool? needsReauth}) =>
      Session(
        serverUrl: serverUrl,
        token: token ?? this.token,
        user: user ?? this.user,
        device: device ?? this.device,
        abilities: abilities ?? this.abilities,
        issuedAt: issuedAt ?? this.issuedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        needsReauth: needsReauth ?? this.needsReauth,
      );

  Map<String, dynamic> toJson() => {
        'server_url': serverUrl,
        'token': token,
        'user': user,
        'device': device,
        'abilities': abilities,
        'issued_at': issuedAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'needs_reauth': needsReauth,
      };

  static Session fromJson(Map<String, dynamic> json) => Session(
        serverUrl: json['server_url'] as String,
        token: json['token'] as String? ?? '',
        user: (json['user'] as Map).cast<String, dynamic>(),
        device: (json['device'] as Map).cast<String, dynamic>(),
        abilities: (json['abilities'] as List).cast<String>(),
        issuedAt: DateTime.tryParse(json['issued_at'] as String? ?? ''),
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        needsReauth: json['needs_reauth'] == true,
      );
}

/// Secrets and identifiers kept in the Android keystore.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const defaultServerUrl = 'http://192.168.101.76/Proximus/public';

  final FlutterSecureStorage _storage;

  /// Generated once per installation and never changed: it is what identifies the phone.
  Future<String> installationId() async {
    final existing = await _read('installation_id');
    if (existing != null) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: 'installation_id', value: created);
    return created;
  }

  Future<String> serverUrl() async => await _read('server_url') ?? defaultServerUrl;

  Future<void> saveServerUrl(String url) => _storage.write(key: 'server_url', value: url.trim());

  Future<Session?> session() async {
    final raw = await _read('session');
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  Future<void> saveSession(Session session) => _storage.write(key: 'session', value: jsonEncode(session.toJson()));

  Future<void> clearSession() => _storage.delete(key: 'session');

  /// Last user whose data is stored locally; another user means starting clean.
  Future<int?> dataOwner() async => int.tryParse(await _read('data_owner') ?? '');

  Future<void> saveDataOwner(int userId) => _storage.write(key: 'data_owner', value: '$userId');

  Future<OfflineCredential?> offlineCredential() async {
    final raw = await _read('offline_credential');
    if (raw == null) return null;
    try {
      return OfflineCredential.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveOfflineCredential(OfflineCredential credential) => _storage.write(key: 'offline_credential', value: jsonEncode(credential.toJson()));

  Future<void> clearOfflineCredential() => _storage.delete(key: 'offline_credential');

  /// Android may keep encrypted values whose key no longer exists (e.g. data restored
  /// on a reinstall). They cannot be read again, so the keystore starts clean.
  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key).timeout(const Duration(seconds: 10));
    } catch (_) {
      try {
        await _storage.deleteAll();
      } catch (_) {}
      return null;
    }
  }
}
