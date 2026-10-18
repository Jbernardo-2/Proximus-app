import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proximus_app/app/brand.dart';
import 'package:proximus_app/app/providers.dart';
import 'package:proximus_app/app/theme.dart';
import 'package:proximus_app/core/session.dart';
import 'package:proximus_app/features/login/login_screen.dart';

class _FakeSecureStore extends SecureStore {
  @override
  Future<String> serverUrl() async => 'http://proximus.test';

  @override
  Future<Session?> session() async => null;
}

void main() {
  testWidgets('shows the Proximus logo and toggles password visibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStoreProvider.overrideWithValue(_FakeSecureStore())],
        child: MaterialApp(theme: buildTheme(), home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProximusLogo), findsOneWidget);

    final editableText = find.descendant(
      of: find.byKey(const Key('login_password_field')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editableText).obscureText, isTrue);
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toggle_password_visibility')));
    await tester.pump();

    expect(tester.widget<EditableText>(editableText).obscureText, isFalse);
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
    expect(find.text('Cambiar servidor'), findsOneWidget, reason: 'development builds can point at any server');
  });

  testWidgets('the client build offers no way to change the server', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStoreProvider.overrideWithValue(_FakeSecureStore())],
        child: MaterialApp(theme: buildTheme(), home: const LoginScreen(canChangeServer: false)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cambiar servidor'), findsNothing);
    expect(find.text('Servidor'), findsNothing);
  });
}
