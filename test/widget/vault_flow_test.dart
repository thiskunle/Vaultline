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

Future<void> launch(WidgetTester tester, MemorySecureStore store, {Biometrics? biometrics}) async {
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

void main() {
  testWidgets('first launch: weak and mismatched PINs are refused, then the vault opens', (tester) async {
    final store = MemorySecureStore();
    await launch(tester, store);
    expect(find.text('Create your vault PIN'), findsOneWidget);

    await typePin(tester, '123456');
    expect(find.text('That PIN is too easy to guess. Try another.'), findsOneWidget);

    await typePin(tester, '482913');
    expect(find.text('Confirm your PIN'), findsOneWidget);
    await typePin(tester, '482914');
    expect(find.text('Those PINs didn’t match. Start again.'), findsOneWidget);
    expect(find.text('Create your vault PIN'), findsOneWidget);

    await typePin(tester, '482913');
    await typePin(tester, '482913');
    await settle(tester, steps: 30);
    expect(find.text('Your vault'), findsOneWidget);

    // Only a salted hash is stored, never the PIN.
    expect(store.values.values.join(), isNot(contains('482913')));
  });

  testWidgets('relaunch: wrong PIN is refused, right PIN opens, lock button locks', (tester) async {
    await launch(tester, await storeWithPin('482913'));
    expect(find.text('Enter your PIN'), findsOneWidget);

    await typePin(tester, '111222');
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);

    await typePin(tester, '482913');
    await settle(tester, steps: 30);
    expect(find.text('Your vault'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lock-button')));
    await settle(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);
  });

  testWidgets('five wrong PINs start a timed lockout and disable the keypad', (tester) async {
    await launch(tester, await storeWithPin('482913'));
    for (var i = 0; i < 4; i++) {
      await typePin(tester, '111222');
    }
    expect(find.textContaining('1 try left before a timed lock'), findsOneWidget);
    await typePin(tester, '111222');
    expect(find.textContaining('Too many attempts. Try again in'), findsOneWidget);

    // Keys do nothing while locked out, even the right PIN.
    await typePin(tester, '482913');
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('Your vault'), findsNothing);
  });

  testWidgets('biometrics: offered at setup, then unlock without the PIN', (tester) async {
    final store = MemorySecureStore();
    final bio = FakeBiometrics(kind: BiometricKind.face);
    await launch(tester, store, biometrics: bio);
    await typePin(tester, '482913');
    await typePin(tester, '482913');
    await settle(tester);
    expect(find.text('Unlock with Face ID?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enable-biometric')));
    await settle(tester, steps: 30);
    expect(find.text('Your vault'), findsOneWidget);
    expect(store.values['vaultline.biometric.v1'], 'on');

    // Lock, and the next unlock prompts for Face ID automatically.
    await tester.tap(find.byKey(const Key('lock-button')));
    await settle(tester, steps: 30);
    expect(bio.prompts, 2);
    expect(find.text('Your vault'), findsOneWidget);
  });

  testWidgets('a failed biometric check leaves the vault locked', (tester) async {
    final store = await storeWithPin('482913');
    await store.write('vaultline.biometric.v1', 'on');
    final bio = FakeBiometrics(kind: BiometricKind.fingerprint, succeed: false);
    await launch(tester, store, biometrics: bio);
    await settle(tester);
    expect(bio.prompts, 1);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.byKey(const Key('biometric-key')), findsOneWidget);
  });
}
