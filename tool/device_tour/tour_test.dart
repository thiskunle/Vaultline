// Device tour: real PIN hashing (background isolate) and the real biometric
// plugin, with in-memory storage so each run starts fresh. Captures key
// frames and reports how long PIN hashing takes on the device.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vaultline/app.dart';
import 'package:vaultline/providers/vault_providers.dart';
import 'package:vaultline/security/pin_hasher.dart';
import 'package:vaultline/security/secure_store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var converted = false;

  Future<void> wait(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (Platform.isAndroid && !converted) {
      converted = true;
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> type(WidgetTester tester, String pin) async {
    for (final d in pin.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await wait(tester, const Duration(milliseconds: 90));
    }
  }

  testWidgets('vault tour', (tester) async {
    // Time the real hash on this device (release builds are faster still).
    final sw = Stopwatch()..start();
    final record = await const PinHasher().create('482913');
    final createMs = sw.elapsedMilliseconds;
    sw.reset();
    final ok = await const PinHasher().verify('482913', record);
    // ignore: avoid_print
    print(
      'PBKDF2 ${PinHasher.defaultIterations} iterations: create ${createMs}ms, verify ${sw.elapsedMilliseconds}ms, ok=$ok',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStoreProvider.overrideWithValue(MemorySecureStore())],
        child: const VaultlineApp(),
      ),
    );
    await wait(tester, const Duration(seconds: 1));
    await shot(tester, '01_create_pin');

    await type(tester, '482913');
    await wait(tester, const Duration(milliseconds: 400));
    await type(tester, '4829');
    await shot(tester, '02_confirm_typing');
    await type(tester, '13');
    await wait(tester, const Duration(milliseconds: 1500));
    await shot(tester, '03_door_opening');
    await wait(tester, const Duration(seconds: 3));
    expect(find.text('Authenticator'), findsOneWidget);
    await shot(tester, '04_vault_open');

    // Add three accounts through the real UI (demo keys, not real secrets).
    const demo = {
      'GitHub': ('ada@example.com', 'JBSW Y3DP EHPK 3PXP'),
      'Google': ('ada.lovelace@gmail.com', 'MFRGGZDFMZTWQ2LKNNWG23TPOBYXE43U'),
      'Dropbox': ('ada@grambyte.ca', 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
    };
    var first = true;
    for (final MapEntry(key: issuer, value: (name, key)) in demo.entries) {
      await tester.tap(find.byKey(Key(first ? 'add-first-account' : 'add-account')));
      await wait(tester, const Duration(milliseconds: 700));
      // The add-method sheet: type the key.
      await tester.tap(find.byKey(const Key('add-via-key')));
      await wait(tester, const Duration(milliseconds: 700));
      await tester.enterText(find.byKey(const Key('field-issuer')), issuer);
      await tester.enterText(find.byKey(const Key('field-name')), name);
      await tester.enterText(find.byKey(const Key('field-secret')), key);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await wait(tester, const Duration(milliseconds: 900));
      if (first) {
        // Close the keyboard and let the page transition fully settle.
        FocusManager.instance.primaryFocus?.unfocus();
        await wait(tester, const Duration(milliseconds: 1500));
        await shot(tester, '05_add_account');
      }
      await tester.ensureVisible(find.byKey(const Key('save-account')));
      await wait(tester, const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('save-account')));
      await wait(tester, const Duration(milliseconds: 900));
      first = false;
    }
    await wait(tester, const Duration(milliseconds: 1500));
    expect(find.text('Dropbox'), findsOneWidget);
    await shot(tester, '06_codes');

    await tester.tap(find.byKey(const Key('lock-button')));
    await wait(tester, const Duration(seconds: 1));
    await shot(tester, '05_locked');

    await type(tester, '111222');
    await wait(tester, const Duration(milliseconds: 1500));
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    await shot(tester, '06_wrong_pin');

    await type(tester, '482913');
    await wait(tester, const Duration(milliseconds: 1400));
    await shot(tester, '07_unlocking');
    // Wheel (0.9 s) and bolts (0.3 s) done: the door swings open (0.75 s).
    await wait(tester, const Duration(milliseconds: 450));
    await shot(tester, '08_door_swinging');
    await wait(tester, const Duration(milliseconds: 300));
    await shot(tester, '09_door_open');
    await wait(tester, const Duration(seconds: 3));
    expect(find.text('Authenticator'), findsOneWidget);
  });
}
