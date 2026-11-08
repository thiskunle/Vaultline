// Shared helpers for widget tests: test doubles, app launch and PIN entry.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultline/app.dart';
import 'package:vaultline/providers/vault_providers.dart';
import 'package:vaultline/security/biometrics.dart';
import 'package:vaultline/security/lock_service.dart';
import 'package:vaultline/security/pin_hasher.dart';
import 'package:vaultline/security/secure_store.dart';

class FakeBiometrics implements Biometrics {
  FakeBiometrics({this.kind = BiometricKind.none, this.succeed = true});
  final BiometricKind kind;
  bool succeed;
  int prompts = 0;

  @override
  Future<BiometricKind> available() async => kind;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

Future<void> launch(
  WidgetTester tester,
  MemorySecureStore store, {
  Biometrics? biometrics,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(store),
        biometricsProvider.overrideWithValue(biometrics ?? FakeBiometrics()),
        pinHasherProvider.overrideWithValue(const PinHasher(iterations: 1000, inBackground: false)),
        if (clock != null) clockProvider.overrideWithValue(clock),
      ],
      child: const VaultlineApp(),
    ),
  );
  await settle(tester);
}

Future<void> settle(WidgetTester tester, {int steps = 20}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('key-$d')));
    await tester.pump();
  }
  await settle(tester);
}

Future<MemorySecureStore> storeWithPin(String pin) async {
  final store = MemorySecureStore();
  await LockService(store: store, hasher: const PinHasher(iterations: 1000, inBackground: false)).setPin(pin);
  return store;
}
