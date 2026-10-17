import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/providers.dart';
import 'app/theme.dart';
import 'data/database.dart';
import 'features/bodega/presentation/assign_orders_screen.dart';
import 'features/bodega/presentation/counts_screen.dart';
import 'features/bodega/presentation/new_receipt_screen.dart';
import 'features/bodega/presentation/product_detail_screen.dart';
import 'features/bodega/presentation/product_search_screen.dart';
import 'features/bodega/presentation/receipts_screen.dart';
import 'features/bodega/presentation/warehouse_run_screen.dart';
import 'features/bodega/presentation/warehouse_runs_screen.dart';
import 'features/home/home_screen.dart';
import 'features/supervision/presentation/field_screen.dart';
import 'features/supervision/presentation/settlement_screen.dart';
import 'features/preventa/presentation/customer_screen.dart';
import 'features/preventa/presentation/customers_screen.dart';
import 'features/preventa/presentation/daily_route_screen.dart';
import 'features/preventa/presentation/new_customer_screen.dart';
import 'features/preventa/presentation/order_detail_screen.dart';
import 'features/preventa/presentation/order_screen.dart';
import 'features/preventa/presentation/payment_screen.dart';
import 'features/preventa/presentation/visited_stops_screen.dart';
import 'features/login/login_screen.dart';
import 'features/reparto/presentation/delivery_outcome_screen.dart';
import 'features/reparto/presentation/delivery_payment_screen.dart';
import 'features/reparto/presentation/delivery_run_screen.dart';
import 'features/reparto/presentation/delivery_stop_screen.dart';
import 'features/reparto/presentation/run_closing_screen.dart';
import 'features/reparto/presentation/run_debts_screen.dart';
import 'features/reparto/presentation/truck_load_screen.dart';
import 'features/session/settings_screen.dart';
import 'features/sync/sync_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(AppDatabase())],
    child: const ProximusApp(),
  ));
}

final _routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/',
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider).value != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      return atLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen(), routes: [
        GoRoute(path: 'sync', builder: (_, _) => const SyncScreen()),
        GoRoute(path: 'settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(path: 'route', builder: (_, _) => const DailyRouteScreen(), routes: [
          GoRoute(path: 'visited', builder: (_, _) => const VisitedStopsScreen()),
        ]),
        GoRoute(path: 'customers', builder: (_, _) => const CustomersScreen(), routes: [
          GoRoute(path: 'new', builder: (_, _) => const NewCustomerScreen()),
        ]),
        GoRoute(path: 'payment/:id', builder: (_, state) => PaymentScreen(customerId: state.pathParameters['id']!)),
        GoRoute(path: 'order/:id', builder: (_, state) => OrderScreen(customerId: state.pathParameters['id']!)),
        GoRoute(path: 'customer/:id', builder: (_, state) => CustomerScreen(customerId: state.pathParameters['id']!)),
        GoRoute(path: 'deliveries', builder: (_, _) => const DeliveryRunScreen(), routes: [
          GoRoute(path: ':runId', builder: (_, state) => DeliveryRunDetailScreen(runId: state.pathParameters['runId']!), routes: [
            GoRoute(path: 'done', builder: (_, state) => DoneStopsScreen(runId: state.pathParameters['runId']!)),
            GoRoute(path: 'closing', builder: (_, state) => RunClosingScreen(runId: state.pathParameters['runId']!)),
            GoRoute(path: 'load', builder: (_, state) => TruckLoadScreen(runId: state.pathParameters['runId']!)),
            GoRoute(path: 'debts', builder: (_, state) => RunDebtsScreen(runId: state.pathParameters['runId']!)),
            GoRoute(path: 'stops/:stopId', builder: (_, state) => DeliveryStopScreen(runId: state.pathParameters['runId']!, stopId: state.pathParameters['stopId']!), routes: [
              GoRoute(path: 'outcome', builder: (_, state) => DeliveryOutcomeScreen(runId: state.pathParameters['runId']!, stopId: state.pathParameters['stopId']!)),
              GoRoute(path: 'payment', builder: (_, state) => DeliveryPaymentScreen(runId: state.pathParameters['runId']!, stopId: state.pathParameters['stopId']!)),
            ]),
          ]),
        ]),
        GoRoute(path: 'products', builder: (_, state) => ProductSearchScreen(scanOnOpen: state.uri.queryParameters['scan'] == '1'), routes: [
          GoRoute(path: ':id', builder: (_, state) => ProductDetailScreen(productId: state.pathParameters['id']!)),
        ]),
        GoRoute(path: 'warehouse-runs', builder: (_, _) => const WarehouseRunsScreen(), routes: [
          GoRoute(path: ':id', builder: (_, state) => WarehouseRunScreen(runId: state.pathParameters['id']!), routes: [
            GoRoute(path: 'orders', builder: (_, state) => AssignOrdersScreen(runId: state.pathParameters['id']!)),
          ]),
        ]),
        GoRoute(path: 'counts', builder: (_, _) => const CountsScreen()),
        GoRoute(path: 'field', builder: (_, _) => const FieldScreen()),
        GoRoute(path: 'settlements', builder: (_, _) => const SettlementsScreen(), routes: [
          GoRoute(path: ':id', builder: (_, state) => SettlementScreen(runId: state.pathParameters['id']!)),
        ]),
        GoRoute(path: 'receipts', builder: (_, _) => const ReceiptsScreen(), routes: [
          GoRoute(path: 'new', builder: (_, _) => const NewReceiptScreen()),
          GoRoute(path: ':id', builder: (_, state) => ReceiptDetailScreen(receiptId: state.pathParameters['id']!)),
        ]),
        GoRoute(path: 'orders/:key', builder: (_, state) => OrderDetailScreen(orderKey: state.pathParameters['key']!)),
      ]),
    ],
  );
});

final _messenger = GlobalKey<ScaffoldMessengerState>();

class ProximusApp extends ConsumerWidget {
  const ProximusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider).isLoading) {
      return MaterialApp(theme: buildTheme(), home: const Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    // A rejection is told right away, on whatever screen the user is, not found later in Actividad.
    ref.listen(syncProvider.select((status) => status.lastReport), (previous, report) {
      if (report == null || report.rejected == 0 || identical(previous, report)) return;
      _messenger.currentState?.showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 8),
        content: Text(report.rejected == 1 ? 'El servidor rechazó 1 operación.' : 'El servidor rechazó ${report.rejected} operaciones.'),
        action: SnackBarAction(label: 'Ver', textColor: Colors.white, onPressed: () => ref.read(_routerProvider).go('/sync')),
      ));
    });

    return MaterialApp.router(
      scaffoldMessengerKey: _messenger,
      title: 'Proximus',
      theme: buildTheme(),
      routerConfig: ref.watch(_routerProvider),
      locale: const Locale('es', 'HN'),
      supportedLocales: const [Locale('es', 'HN'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
    );
  }
}
