import 'package:dio/dio.dart';

/// Error answered by the server, or a network failure (status null).
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code, this.errors});

  final String message;
  final int? status;

  /// Machine code sent by the server, e.g. `device_revoked`.
  final String? code;
  final Map<String, dynamic>? errors;

  bool get isNetwork => status == null;
  bool get isUnauthorized => status == 401;
  bool get isDeviceRevoked => status == 423 || code == 'device_revoked';

  @override
  String toString() => message;
}

/// Calls the sync engine needs; faked in tests.
abstract interface class SyncApi {
  Future<Map<String, dynamic>> manifest();

  Future<Map<String, dynamic>> pull(String resource, {String? cursor, int limit});

  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> operations);
}

class ProximusApi implements SyncApi {
  ProximusApi({required String baseUrl, String? token, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
              headers: {'Accept': 'application/json'},
            )) {
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  final Dio _dio;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String installationId,
    required String deviceName,
    required String appVersion,
  }) =>
      _send(() => _dio.post('/tokens', data: {
            'email': email,
            'password': password,
            'installation_id': installationId,
            'device_name': deviceName,
            'platform': 'android',
            'app_version': appVersion,
          }));

  Future<void> logout() => _send(() => _dio.delete('/tokens/current'));

  /// A new token for this phone with a fresh expiry.
  Future<Map<String, dynamic>> refresh() => _send(() => _dio.post('/tokens/refresh'));

  @override
  Future<Map<String, dynamic>> manifest() => _send(() => _dio.get('/sync'));

  @override
  Future<Map<String, dynamic>> pull(String resource, {String? cursor, int limit = 200}) => _send(
        () => _dio.get('/sync/pull/$resource', queryParameters: {'cursor': ?cursor, 'limit': limit}),
      );

  @override
  Future<Map<String, dynamic>> push(List<Map<String, dynamic>> operations) =>
      _send(() => _dio.post('/sync/push', data: {'operations': operations}));

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final data = response.data;
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on DioException catch (error) {
      final response = error.response;
      if (response == null) {
        throw ApiException('Sin conexión con el servidor.');
      }
      final body = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : const <String, dynamic>{};
      throw ApiException(
        (body['message'] as String?) ?? 'El servidor respondió con un error (${response.statusCode}).',
        status: response.statusCode,
        code: body['code'] as String?,
        errors: body['errors'] as Map<String, dynamic>?,
      );
    }
  }
}
