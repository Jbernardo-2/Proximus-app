import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Values the server accepts in `location.status`.
enum LocationCaptureStatus {
  captured('captured'),
  denied('denied'),
  unavailable('unavailable');

  const LocationCaptureStatus(this.value);

  final String value;
}

/// Where the phone was when something happened, or why it is unknown.
final class LocationCapture {
  const LocationCapture._({required this.status, this.position, this.message});

  factory LocationCapture.captured(Position position) =>
      LocationCapture._(status: LocationCaptureStatus.captured, position: position);

  factory LocationCapture.failure(LocationCaptureStatus status, String message) =>
      LocationCapture._(status: status, message: message);

  final LocationCaptureStatus status;
  final Position? position;
  final String? message;

  bool get wasCaptured => position != null;

  /// `location` of an operation (contract section 4). [occurredAt] is when the fact
  /// happened: the server uses it as the visit time, so it is sent even without a fix.
  Map<String, dynamic> toPayload(DateTime occurredAt) {
    final value = position;
    return {
      'status': status.value,
      if (value != null) ...{
        'latitude': value.latitude,
        'longitude': value.longitude,
        'accuracy': value.accuracy,
      },
      'captured_at': occurredAt.toUtc().toIso8601String(),
    };
  }
}

abstract interface class LocationGateway {
  Future<bool> isServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position?> lastKnownPosition();
  Future<Position> currentPosition();
}

final class GeolocatorLocationGateway implements LocationGateway {
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<Position> currentPosition() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<Position?> lastKnownPosition() => Geolocator.getLastKnownPosition();

  @override
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();
}

final class LocationCaptureService {
  LocationCaptureService({LocationGateway? gateway, DateTime Function()? clock})
      : _gateway = gateway ?? GeolocatorLocationGateway(),
        _clock = clock ?? DateTime.now;

  static const maximumCachedAge = Duration(minutes: 2);

  final LocationGateway _gateway;
  final DateTime Function() _clock;

  /// Asks for the position. It may take a while; use [LocationSession] so saving never waits for it.
  Future<LocationCapture> capture() async {
    try {
      if (!await _gateway.isServiceEnabled()) {
        return LocationCapture.failure(LocationCaptureStatus.unavailable, 'La ubicación del teléfono está apagada.');
      }
      var permission = await _gateway.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _gateway.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return LocationCapture.failure(LocationCaptureStatus.denied, 'Proximus no tiene permiso para usar la ubicación.');
      }

      final cached = await _gateway.lastKnownPosition();
      if (cached != null && _clock().difference(cached.timestamp).abs() <= maximumCachedAge) {
        return LocationCapture.captured(cached);
      }
      return LocationCapture.captured(await _gateway.currentPosition());
    } catch (_) {
      return LocationCapture.failure(LocationCaptureStatus.unavailable, 'No se obtuvo la ubicación.');
    }
  }

  /// Starts looking for the position now (e.g. when the customer is opened).
  LocationSession start() => LocationSession._(capture());
}

/// A capture already in progress. Saving takes whatever is ready and never blocks.
final class LocationSession {
  LocationSession._(this._pending) {
    _pending.then((value) => _result = value);
  }

  final Future<LocationCapture> _pending;
  LocationCapture? _result;

  /// The position if it arrived, waiting at most [grace]; otherwise "unavailable".
  Future<LocationCapture> take({Duration grace = const Duration(milliseconds: 1500)}) async {
    final ready = _result;
    if (ready != null) return ready;
    return _pending.timeout(
      grace,
      onTimeout: () => LocationCapture.failure(LocationCaptureStatus.unavailable, 'La ubicación no llegó a tiempo.'),
    );
  }
}
