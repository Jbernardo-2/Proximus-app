import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Lets the last user of this phone open the app without signal. Only a salted
/// PBKDF2 fingerprint of the password is kept, never the password itself.
final class OfflineCredential {
  const OfflineCredential({
    required this.email,
    required this.salt,
    required this.hash,
    required this.iterations,
    required this.session,
    this.failedAttempts = 0,
  });

  /// Built right after an online login succeeded with this password.
  factory OfflineCredential.create({required String email, required String password, required Map<String, dynamic> session, int iterations = defaultIterations}) {
    final random = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    return OfflineCredential(
      email: _normalize(email),
      salt: base64Encode(salt),
      hash: base64Encode(pbkdf2(password, salt, iterations)),
      iterations: iterations,
      session: session,
    );
  }

  factory OfflineCredential.fromJson(Map<String, dynamic> json) => OfflineCredential(
        email: json['email'] as String,
        salt: json['salt'] as String,
        hash: json['hash'] as String,
        iterations: (json['iterations'] as num).toInt(),
        session: (json['session'] as Map).cast<String, dynamic>(),
        failedAttempts: (json['failed_attempts'] as num?)?.toInt() ?? 0,
      );

  static const defaultIterations = 60000;

  /// After this many wrong passwords offline, only an online login opens the app.
  static const maxAttempts = 5;

  final String email;
  final String salt;
  final String hash;
  final int iterations;

  /// Session data (user, device, abilities, server) to open the app with, minus a valid token.
  final Map<String, dynamic> session;
  final int failedAttempts;

  bool get locked => failedAttempts >= maxAttempts;

  bool matches(String email, String password) {
    if (_normalize(email) != this.email) return false;
    final candidate = pbkdf2(password, base64Decode(salt), iterations);
    return _constantTimeEquals(candidate, base64Decode(hash));
  }

  OfflineCredential withFailedAttempt() => OfflineCredential(
        email: email,
        salt: salt,
        hash: hash,
        iterations: iterations,
        session: session,
        failedAttempts: failedAttempts + 1,
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        'salt': salt,
        'hash': hash,
        'iterations': iterations,
        'session': session,
        'failed_attempts': failedAttempts,
      };

  static String _normalize(String email) => email.trim().toLowerCase();

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

/// PBKDF2 with HMAC-SHA256 (RFC 8018), one 32-byte block.
Uint8List pbkdf2(String password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(password));
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = Uint8List.fromList(block);
  for (var i = 1; i < iterations; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return result;
}

/// Builds the credential in a background isolate. Top-level on purpose: only the
/// arguments travel to the isolate, never the caller's surroundings (database, providers).
Future<OfflineCredential> createCredentialInBackground({required String email, required String password, required Map<String, dynamic> session}) {
  final args = (email: email, password: password, session: session);
  return Isolate.run(() => OfflineCredential.create(email: args.email, password: args.password, session: args.session));
}

/// Checks a password against a credential in a background isolate (PBKDF2 takes a moment).
Future<bool> verifyCredentialInBackground(OfflineCredential credential, String email, String password) {
  final args = (json: credential.toJson(), email: email, password: password);
  return Isolate.run(() => OfflineCredential.fromJson(args.json).matches(args.email, args.password));
}
