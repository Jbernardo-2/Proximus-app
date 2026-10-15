import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/core/api.dart';
import 'package:proximus_app/core/offline_credential.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/data/database.dart';

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Keystore double with every value in memory.
class MemoryStore extends SecureStore {
  Session? current;
  OfflineCredential? credential;
  int? owner;

  @override
  Future<Session?> session() async => current;
  @override
  Future<void> saveSession(Session session) async => current = session;
  @override
  Future<void> clearSession() async => current = null;
  @override
  Future<String> installationId() async => 'instalacion-prueba';
  @override
  Future<String> serverUrl() async => unreachable;
  @override
  Future<void> saveServerUrl(String url) async {}
  @override
  Future<int?> dataOwner() async => owner;
  @override
  Future<void> saveDataOwner(int userId) async => owner = userId;
  @override
  Future<OfflineCredential?> offlineCredential() async => credential;
  @override
  Future<void> saveOfflineCredential(OfflineCredential value) async => credential = value;
  @override
  Future<void> clearOfflineCredential() async => credential = null;
}

/// Nothing listens there: the login fails as it does without signal.
const unreachable = 'http://127.0.0.1:9';

Map<String, dynamic> storedSession() => Session(
      serverUrl: unreachable,
      token: '',
      user: const {'id': 7, 'name': 'Ana Preventista', 'role': 'preventista', 'email': 'ana@proximus.hn'},
      device: const {'code': 'M001'},
      abilities: const ['orders:manage'],
    ).toJson();

void main() {
  test('PBKDF2-HMAC-SHA256 matches the standard test vectors', () {
    expect(hex(pbkdf2('password', 'salt'.codeUnits, 1)), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(hex(pbkdf2('password', 'salt'.codeUnits, 2)), 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
  });

  test('the credential keeps only a fingerprint and locks after five failures', () {
    var credential = OfflineCredential.create(email: ' Ana@Proximus.hn ', password: 'secreta123', session: storedSession(), iterations: 1000);
    expect(credential.toJson().toString(), isNot(contains('secreta123')));
    expect(credential.matches('ana@proximus.hn', 'secreta123'), isTrue);
    expect(credential.matches('ana@proximus.hn', 'Secreta123'), isFalse);
    expect(credential.matches('otro@proximus.hn', 'secreta123'), isFalse);

    for (var i = 0; i < OfflineCredential.maxAttempts; i++) {
      credential = credential.withFailedAttempt();
    }
    expect(credential.locked, isTrue);
  });

  test('a token is renewed once it is a week old, never while the server does not accept the session', () {
    final now = DateTime(2026, 10, 20);
    Session session({DateTime? issued, String token = 't', bool reauth = false}) =>
        Session(serverUrl: unreachable, token: token, user: const {'id': 1}, device: const {}, abilities: const [], issuedAt: issued, needsReauth: reauth);

    expect(session(issued: now.subtract(const Duration(days: 3))).shouldRenew(now), isFalse);
    expect(session(issued: now.subtract(const Duration(days: 8))).shouldRenew(now), isTrue);
    expect(session().shouldRenew(now), isTrue, reason: 'sessions from before this version');
    expect(session(issued: now.subtract(const Duration(days: 8)), reauth: true).shouldRenew(now), isFalse);
    expect(session(token: '').canSync, isFalse);
  });

  test('online login, sign out and sign in again without signal (the real sequence on the phone)', () async {
    final store = MemoryStore();
    final db = AppDatabase(NativeDatabase.memory());
    final server = FakeServer();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      secureStoreProvider.overrideWithValue(store),
      sessionApiProvider.overrideWithValue((baseUrl, {token}) => FakeServerApi(server, baseUrl: baseUrl, token: token)),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container.read(sessionProvider.future);
    final sessions = container.read(sessionProvider.notifier);

    await sessions.login(email: 'Ana@Proximus.hn', password: 'secreta123', serverUrl: unreachable);
    expect(container.read(sessionProvider).value!.canSync, isTrue);
    expect(store.credential, isNotNull, reason: 'the online login leaves the fingerprint for entering without signal');

    server.online = false;
    await sessions.prepareLogout();
    await sessions.endSession();
    expect(container.read(sessionProvider).value, isNull);

    Object? offlineError;
    try {
      await sessions.login(email: 'ana@proximus.hn', password: 'mala', serverUrl: unreachable);
    } catch (error) {
      offlineError = error;
    }
    expect(offlineError, isA<ApiException>().having((e) => e.isNetwork, 'shown as is, not as a network error', isFalse));

    await sessions.login(email: 'ana@proximus.hn', password: 'secreta123', serverUrl: unreachable);
    final offline = container.read(sessionProvider).value!;
    expect(offline.userName, 'Ana Preventista');
    expect(offline.needsReauth, isTrue);

    server.online = true;
    await sessions.login(email: offline.email, password: 'secreta123', serverUrl: unreachable);
    expect(container.read(sessionProvider).value!.canSync, isTrue, reason: 'back online, the same user gets a session the server accepts');
  });

  group('signing in without signal', () {
    late MemoryStore store;
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      store = MemoryStore()
        ..owner = 7
        ..credential = OfflineCredential.create(email: 'ana@proximus.hn', password: 'secreta123', session: storedSession(), iterations: 1000);
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db), secureStoreProvider.overrideWithValue(store)]);
      await container.read(sessionProvider.future);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> login(String email, String password) =>
        container.read(sessionProvider.notifier).login(email: email, password: password, serverUrl: unreachable);

    test('the last user of the phone enters and works until the server accepts the session again', () async {
      await login('ana@proximus.hn', 'secreta123');

      final session = container.read(sessionProvider).value!;
      expect(session.userName, 'Ana Preventista');
      expect(session.needsReauth, isTrue);
      expect(session.canSync, isFalse);
      expect(container.read(apiProvider), isNull, reason: 'nothing is sent with a session the server does not accept');
    });

    test('a wrong password counts down the offline attempts', () async {
      await expectLater(login('ana@proximus.hn', 'otra'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Te quedan 4'))));
      expect(store.credential!.failedAttempts, 1);
      expect(container.read(sessionProvider).value, isNull);
    });

    test('another user cannot enter without signal', () async {
      await expectLater(login('luis@proximus.hn', 'secreta123'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('último usuario'))));
    });
  });
}

class FakeServer {
  bool online = true;
}

/// The server answers like Laravel does, or fails like a phone without signal.
class FakeServerApi extends ProximusApi {
  FakeServerApi(this.server, {required super.baseUrl, super.token});

  final FakeServer server;

  void _requireSignal() {
    if (!server.online) throw ApiException('Sin conexión con el servidor.');
  }

  @override
  Future<Map<String, dynamic>> login({required String email, required String password, required String installationId, required String deviceName, required String appVersion}) async {
    _requireSignal();
    if (password != 'secreta123') throw ApiException('Las credenciales proporcionadas no son válidas.', status: 422);
    return {
      'token': '12|token',
      'abilities': ['orders:manage'],
      'expires_at': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      'user': {'id': 7, 'name': 'Ana Preventista', 'role': 'preventista'},
      'device': {
        'code': 'M001',
        'series': {'invoice': {'prefix': 'FAC-M001-', 'last_number': 0}},
      },
    };
  }

  @override
  Future<void> logout() async => _requireSignal();

  @override
  Future<Map<String, dynamic>> manifest() async {
    _requireSignal();
    return {'resources': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> operations) async {
    _requireSignal();
    return {'results': <Map<String, dynamic>>[]};
  }
}
