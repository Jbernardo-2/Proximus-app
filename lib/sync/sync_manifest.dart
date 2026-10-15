import 'dart:convert';

final class SyncManifest {
  const SyncManifest({
    required this.resources,
    required this.operations,
    required this.defaultWarehouse,
    this.catalogs = const {},
  });

  factory SyncManifest.fromJson(Map<String, dynamic> json) => SyncManifest(
        resources: (json['resources'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), SyncResource.fromJson((value as Map).cast<String, dynamic>())),
        ),
        operations: (json['operations'] as List? ?? const []).map((value) => value.toString()).toSet(),
        defaultWarehouse: json['default_warehouse'] is Map
            ? (json['default_warehouse'] as Map).cast<String, dynamic>()
            : null,
        catalogs: (json['catalogs'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key.toString(), [
            for (final item in value as List? ?? const []) (item as Map).cast<String, dynamic>(),
          ]),
        ),
      );

  factory SyncManifest.decode(String source) =>
      SyncManifest.fromJson((jsonDecode(source) as Map).cast<String, dynamic>());

  final Map<String, SyncResource> resources;
  final Set<String> operations;
  final Map<String, dynamic>? defaultWarehouse;

  /// Server lists such as visit_reasons or payment_methods: value, label and flags.
  final Map<String, List<Map<String, dynamic>>> catalogs;

  List<({String value, String label})> options(String catalog) => [
        for (final item in catalogs[catalog] ?? const <Map<String, dynamic>>[])
          (value: item['value'].toString(), label: item['label'].toString()),
      ];

  bool hasResource(String name) => resources[name]?.available ?? false;
  bool supports(String operation) => operations.contains(operation);
}

final class SyncResource {
  const SyncResource({required this.mode, required this.available});

  factory SyncResource.fromJson(Map<String, dynamic> json) => SyncResource(
        mode: json['mode'] as String? ?? '',
        available: json['available'] == true,
      );

  final String mode;
  final bool available;
}
