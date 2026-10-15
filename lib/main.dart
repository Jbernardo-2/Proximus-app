import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/providers.dart';
import 'app/theme.dart';
import 'data/database.dart';
import 'features/home/home_screen.dart';
import 'features/preventa/presentation/customer_screen.dart';
import 'features/preventa/presentation/customers_screen.dart';
import 'features/preventa/presentation/daily_route_screen.dart';
import 'features/preventa/presentation/order_screen.dart';
import 'features/login/login_screen.dart';
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
        GoRoute(path: 'route', builder: (_, _) => const DailyRouteScreen()),
        GoRoute(path: 'customers', builder: (_, _) => const CustomersScreen()),
        GoRoute(path: 'order/:id', builder: (_, state) => OrderScreen(customerId: state.pathParameters['id']!)),
        GoRoute(path: 'customer/:id', builder: (_, state) => CustomerScreen(customerId: state.pathParameters['id']!)),
      ]),
    ],
  );
});

class ProximusApp extends ConsumerWidget {
  const ProximusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider).isLoading) {
      return MaterialApp(theme: buildTheme(), home: const Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    return MaterialApp.router(
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
