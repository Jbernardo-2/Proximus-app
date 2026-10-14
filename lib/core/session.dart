import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Signed-in user and phone, as the server returned them at login.
class Session {
  Session({required this.serverUrl, required this.token, required this.user, required this.device, required this.abilities});

  final String serverUrl;
  final String token;
  final Map<String, dynamic> user;
  final Map<String, dynamic> device;
  final List<String> abilities;

  int get userId => (user['id'] as num).toInt();
  String get userName => user['name'] as String? ?? '';
  String get role => user['role'] as String? ?? '';
  String get deviceCode => device['code'] as String? ?? '';

  bool can(String ability) => abilities.contains(ability);

  Map<String, dynamic> toJson() =>
      {'server_url': serverUrl, 'token': token, 'user': user, 'device': device, 'abilities': abilities};

  static Session fromJson(Map<String, dynamic> json) => Session(
        serverUrl: json['server_url'] as String,
        token: json['token'] as String,
        user: (json['user'] as Map).cast<String, dynamic>(),
        device: (json['device'] as Map).cast<String, dynamic>(),
        abilities: (json['abilities'] as List).cast<String>(),
      );
}

/// Secrets and identifiers kept in the Android keystore.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const defaultServerUrl = 'http://192.168.101.76/Proximus/public';

  final FlutterSecureStorage _storage;

  /// Generated once per installation and never changed: it is what identifies the phone.
  Future<String> installationId() async {
    final existing = await _storage.read(key: 'installation_id');
    if (existing != null) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: 'installation_id', value: created);
    return created;
  }

  Future<String> serverUrl() async => await _storage.read(key: 'server_url') ?? defaultServerUrl;

  Future<void> saveServerUrl(String url) => _storage.write(key: 'server_url', value: url.trim());

  Future<Session?> session() async {
    final raw = await _storage.read(key: 'session');
    return raw == null ? null : Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSession(Session session) => _storage.write(key: 'session', value: jsonEncode(session.toJson()));

  Future<void> clearSession() => _storage.delete(key: 'session');

  /// Last user whose data is stored locally; another user means starting clean.
  Future<int?> dataOwner() async => int.tryParse(await _storage.read(key: 'data_owner') ?? '');

  Future<void> saveDataOwner(int userId) => _storage.write(key: 'data_owner', value: '$userId');
}
