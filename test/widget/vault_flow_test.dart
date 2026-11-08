import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultline/security/biometrics.dart';
import 'package:vaultline/security/secure_store.dart';

import '../helpers.dart';

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
    expect(find.text('Authenticator'), findsOneWidget);

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
    expect(find.text('Authenticator'), findsOneWidget);

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
    expect(find.text('Authenticator'), findsNothing);
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
    expect(find.text('Authenticator'), findsOneWidget);
    expect(store.values['vaultline.biometric.v1'], 'on');

    // Lock, and the next unlock prompts for Face ID automatically.
    await tester.tap(find.byKey(const Key('lock-button')));
    await settle(tester, steps: 30);
    expect(bio.prompts, 2);
    expect(find.text('Authenticator'), findsOneWidget);
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
