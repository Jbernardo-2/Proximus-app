import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:proximus_app/core/decimal_value.dart';
import 'package:proximus_app/core/location_capture.dart';
import 'package:proximus_app/core/ulid.dart';
import 'package:proximus_app/data/database.dart';
import 'package:proximus_app/features/preventa/data/preventa_models.dart';
import 'package:proximus_app/features/preventa/data/preventa_operations.dart';
import 'package:proximus_app/features/preventa/data/preventista_repository.dart';

DecimalValue d(String value) => DecimalValue.parse(value);

Position position(DateTime at) => Position(
      latitude: 14.0723,
      longitude: -87.1921,
      timestamp: at,
      accuracy: 12.5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Map<String, dynamic> stop(String id, int order, {String status = 'pending', String date = '2026-10-14', Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'route_stop_id': id,
      'date': date,
      'visit_order': order,
      'status': status,
      'route': {'id': 'r1', 'name': 'Ruta Centro'},
      'customer': {'id': 'c-$id', 'code': 'CLI-$order', 'business_name': 'Cliente $order', 'address': 'Calle $order'},
      ...extra,
    };

OutboxData op(int id, String type, Map<String, dynamic> payload, {String status = OutboxStatus.pending, DateTime? processedAt, String? message, Map<String, dynamic>? result}) => OutboxData(
      id: id,
      clientReference: 'M001:$id',
      type: type,
      payload: jsonEncode(payload),
      status: status,
      summary: '',
      attempts: 0,
      createdAt: DateTime(2026, 10, 14, 8),
      processedAt: processedAt,
      message: message,
      result: result == null ? null : jsonEncode(result),
    );

void main() {
  final now = DateTime(2026, 10, 14, 10); // Wednesday
  const repository = PreventistaRepository();

  group('DecimalValue', () {
    test('adds and multiplies money without floating point drift', () {
      expect((d('0.1') + d('0.2')).toString(), '0.3');
      expect((d('12') * d('9.5000')).toFixed(4), '114.0000');
      expect(d('2.345').toFixed(2), '2.35');
      expect(d('-2.345').toFixed(2), '-2.35');
      expect(d('10.50') == d('10.5'), isTrue);
    });
  });

  group('price tiers', () {
    final presentation = LocalPresentation.fromJson({
      'id': 'p1',
      'name': 'Fardo',
      'conversion_factor': '24.000000',
      'sale_price': '180.0000',
      'is_base': false,
      'is_sellable': true,
      'is_active': true,
      'price_tiers': [
        {'min_quantity': '10', 'max_quantity': null, 'unit_price': '170.0000', 'is_active': true},
        {'min_quantity': '50', 'max_quantity': '99', 'unit_price': '160.0000', 'is_active': true},
        {'min_quantity': '20', 'unit_price': '150.0000', 'is_active': false},
        {'min_quantity': '5', 'unit_price': '175.0000', 'is_active': true, 'ends_at': '2026-10-13'},
      ],
    });

    test('follow the server rule: active, in force, covering the quantity, highest minimum', () {
      expect(presentation.priceFor(d('3'), now).unitPrice.toFixed(4), '180.0000');
      expect(presentation.priceFor(d('7'), now).unitPrice.toFixed(4), '180.0000', reason: 'the tier from 5 expired yesterday');
      expect(presentation.priceFor(d('25'), now).unitPrice.toFixed(4), '170.0000', reason: 'the tier from 20 is inactive');
      expect(presentation.priceFor(d('60'), now).unitPrice.toFixed(4), '160.0000');
      expect(presentation.priceFor(d('120'), now).unitPrice.toFixed(4), '170.0000', reason: 'above the maximum of the 50-99 tier');
    });
  });

  group('location payload', () {
    test('sends status and the time of the fact even without a fix', () {
      final at = DateTime.utc(2026, 10, 14, 15, 30);
      final failed = LocationCapture.failure(LocationCaptureStatus.denied, 'sin permiso').toPayload(at);
      expect(failed, {'status': 'denied', 'captured_at': '2026-10-14T15:30:00.000Z'});

      final captured = LocationCapture.captured(position(at)).toPayload(at);
      expect(captured['status'], 'captured');
      expect(captured['accuracy'], 12.5);
      expect(captured, contains('latitude'));
    });

    test('saving never waits for a slow GPS', () async {
      final session = LocationCaptureService(gateway: _SlowGateway()).start();
      final stopwatch = Stopwatch()..start();
      final result = await session.take(grace: const Duration(milliseconds: 50));
      expect(result.status, LocationCaptureStatus.unavailable);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('daily route', () {
    test('order and payment of the same customer are both kept', () {
      final route = repository.mergeRouteActivity(
        records: [stop('s1', 1), stop('s2', 2)],
        outbox: [
          op(1, 'order.create', {'customer_id': 'c-s1', 'route_stop_id': 's1', 'items': [{'quantity': '2', 'unit_price': '25.5000'}]}),
          op(2, 'customer.payment', {'customer_id': 'c-s1', 'amount': '40'}),
          op(3, 'visit.no_sale', {'customer_id': 'c-s2'}, status: OutboxStatus.rejected, message: 'Cliente no asignado.'),
        ],
        pulledAt: DateTime(2026, 10, 14, 7),
        now: now,
      );

      final first = route.stops.first;
      expect(first.status, 'order_taken');
      expect(first.activity.hasPayment, isTrue);
      expect(first.operationState, LocalOperationState.pending);
      expect(route.sold.toFixed(2), '51.00');
      expect(route.collected.toFixed(2), '40.00');
      expect(route.stops.last.status, 'pending', reason: 'a rejected operation does not count');
      expect(route.stops.last.operationState, LocalOperationState.rejected);
      expect(route.stops.last.rejectionMessage, 'Cliente no asignado.');
      expect(route.attended, 1);
      expect(route.isStale, isFalse);
    });

    test('operations accepted before the last download are not counted twice', () {
      final route = repository.mergeRouteActivity(
        records: [stop('s1', 1, status: 'order_taken', extra: {'has_order': true, 'orders_total': '51.0000'})],
        outbox: [
          op(1, 'order.create', {'customer_id': 'c-s1', 'route_stop_id': 's1', 'items': [{'quantity': '2', 'unit_price': '25.5'}]},
              status: OutboxStatus.done, processedAt: DateTime(2026, 10, 14, 9)),
        ],
        pulledAt: DateTime(2026, 10, 14, 9, 1),
        now: now,
      );

      expect(route.sold.toFixed(2), '51.00');
      expect(route.stops.single.operationState, LocalOperationState.synchronized);
    });

    test('a customer registered offline for today appears as a new stop', () {
      final payload = PreventaOperations.newCustomer(businessName: 'Pulpería Nueva', address: 'Kennedy', visitDay: now.weekday);
      final route = repository.mergeRouteActivity(
        records: [stop('s1', 1)],
        outbox: [op(1, 'customer.create', payload)],
        pulledAt: null,
        now: now,
      );

      expect(route.stops, hasLength(2));
      expect(route.stops.last.customer.businessName, 'Pulpería Nueva');
      expect(route.stops.last.routeStopId, (payload['route_stop'] as Map)['id']);
      expect(route.stops.last.visitOrder, 2);
    });

    test('a route downloaded another day is flagged', () {
      final route = repository.mergeRouteActivity(records: [stop('s1', 1, date: '2026-10-13')], outbox: const [], pulledAt: null, now: now);
      expect(route.isStale, isTrue);
    });
  });

  group('operations', () {
    test('an order always carries its stop and the location of the visit', () {
      final payload = PreventaOperations.order(
        customerId: 'c1',
        routeStopId: 's1',
        takenAt: DateTime(2026, 10, 14, 9, 5),
        paymentTerm: 'cash',
        items: [(presentationId: 'p1', quantity: d('3'), unitPrice: d('9.5'), notes: null)],
        location: LocationCapture.failure(LocationCaptureStatus.unavailable, ''),
      );

      expect(payload['route_stop_id'], 's1');
      expect(payload['order_date'], '2026-10-14');
      expect(payload.containsKey('requested_delivery_date'), isFalse);
      expect((payload['items'] as List).single['unit_price'], '9.5000');
      expect(payload['location']['status'], 'unavailable');
      expect(PreventistaRepository.orderTotal(payload).toFixed(2), '28.50');
    });

    test('an account payment must add up exactly', () {
      Map<String, dynamic> build(String cash) => PreventaOperations.accountPayment(
            customerId: 'c1',
            receiptNumber: 'ABO-M001-000001',
            amount: d('100'),
            lines: [(method: 'cash', amount: d(cash), reference: null), (method: 'bank_transfer', amount: d('60'), reference: null)],
            allocations: [(receivableId: 'r1', amount: d('100'))],
            at: now,
            location: LocationCapture.failure(LocationCaptureStatus.unavailable, ''),
          );

      expect(build('40')['amount'], '100');
      expect(() => build('30'), throwsArgumentError);
    });

    test('ids generated on the phone are valid ULIDs ordered by time', () {
      final first = Ulid.generate(at: DateTime(2026, 10, 14));
      final second = Ulid.generate(at: DateTime(2026, 10, 15));
      expect(first, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
      expect(first.compareTo(second), lessThan(0));
    });
  });
}

class _SlowGateway implements LocationGateway {
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;

  @override
  Future<Position> currentPosition() => Future.delayed(const Duration(seconds: 5), () => position(DateTime.now()));

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<Position?> lastKnownPosition() async => null;

  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;
}
