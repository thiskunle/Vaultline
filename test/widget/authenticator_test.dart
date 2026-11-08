import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultline/models/otp_account.dart';
import 'package:vaultline/security/secure_store.dart';

import '../helpers.dart';

/// RFC 6238 SHA-1 key ("12345678901234567890") as people might paste it.
const rfcKey = 'gezd gnbv gy3t qojq gezd gnbv gy3t qojq';

void main() {
  late DateTime now;
  late List<String> clipboard;

  setUp(() {
    // 59 s after the epoch: RFC code 94287082 → 6-digit "287082", 1 s left.
    now = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);
    clipboard = [];
  });

  Future<MemorySecureStore> openVault(WidgetTester tester, {MemorySecureStore? store}) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
    final s = store ?? await storeWithPin('482913');
    await launch(tester, s, clock: () => now);
    await typePin(tester, '482913');
    await settle(tester, steps: 30);
    expect(find.text('Authenticator'), findsOneWidget);
    return s;
  }

  Future<void> addAccount(WidgetTester tester, {String issuer = 'GitHub', String key = rfcKey}) async {
    final first = find.byKey(const Key('add-first-account'));
    await tester.tap(first.evaluate().isNotEmpty ? first : find.byKey(const Key('add-account')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('field-issuer')), issuer);
    await tester.enterText(find.byKey(const Key('field-name')), 'ada@example.com');
    await tester.enterText(find.byKey(const Key('field-secret')), key);
    await settle(tester, steps: 5);
  }

  testWidgets('add an account: live preview, then a ticking code in the list', (tester) async {
    final store = await openVault(tester);
    expect(find.text('No accounts yet'), findsOneWidget);

    await addAccount(tester);
    // Preview shows the right code before saving.
    expect(find.descendant(of: find.byKey(const Key('preview')), matching: find.text('287 082')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await settle(tester, steps: 3);
    await tester.tap(find.byKey(const Key('save-account')));
    await settle(tester);

    expect(find.text('GitHub added'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('287 082'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: '1 second left on the ring');

    // The next time step brings the next RFC code (counter 2 → 359152).
    now = DateTime.fromMillisecondsSinceEpoch(60000, isUtc: true);
    await settle(tester, steps: 3);
    expect(find.text('359 152'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);

    // Saved (normalised) in secure storage.
    final saved = jsonDecode(store.values['vaultline.accounts.v1']!) as List;
    expect(OtpAccount.fromJson(saved.single as Map<String, dynamic>).secret, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
  });

  testWidgets('validation: service required, bad keys explained, duplicates refused', (tester) async {
    await openVault(tester);
    await addAccount(tester, issuer: '', key: 'not a key 1');
    expect(find.textContaining('doesn’t look like a setup key'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await tester.tap(find.byKey(const Key('save-account')));
    await settle(tester, steps: 5);
    expect(find.text('Enter the service name'), findsOneWidget);
    expect(find.text('Authenticator'), findsNothing, reason: 'still on the add screen');

    await tester.enterText(find.byKey(const Key('field-issuer')), 'GitHub');
    await tester.enterText(find.byKey(const Key('field-secret')), rfcKey);
    await settle(tester, steps: 3);
    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await tester.tap(find.byKey(const Key('save-account')));
    await settle(tester);
    expect(find.text('Authenticator'), findsOneWidget);

    // Same key again (different spacing/case) is refused.
    await addAccount(tester, issuer: 'GitHub again', key: rfcKey.toUpperCase().replaceAll(' ', ''));
    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await tester.tap(find.byKey(const Key('save-account')));
    await settle(tester, steps: 5);
    expect(find.text('That account is already in your vault.'), findsOneWidget);
  });

  testWidgets('tap copies the code; delete asks first', (tester) async {
    await openVault(tester);
    await addAccount(tester);
    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await tester.tap(find.byKey(const Key('save-account')));
    await settle(tester);

    await tester.tap(find.text('287 082'));
    await settle(tester, steps: 3);
    expect(clipboard, ['287082']);
    expect(find.text('GitHub code copied'), findsOneWidget);

    await tester.tap(find.byTooltip('More for GitHub'));
    await settle(tester, steps: 5);
    await tester.tap(find.byKey(const Key('delete-account')));
    await settle(tester, steps: 5);
    expect(find.text('Delete GitHub?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester, steps: 5);
    expect(find.text('287 082'), findsOneWidget);

    await tester.tap(find.byTooltip('More for GitHub'));
    await settle(tester, steps: 5);
    await tester.tap(find.byKey(const Key('delete-account')));
    await settle(tester, steps: 5);
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await settle(tester, steps: 5);
    expect(find.text('No accounts yet'), findsOneWidget);
  });

  testWidgets('accounts survive locking and a restart', (tester) async {
    final store = await openVault(tester);
    await addAccount(tester);
    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await tester.tap(find.byKey(const Key('save-account')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('lock-button')));
    await settle(tester);
    expect(find.text('287 082'), findsNothing, reason: 'codes hidden while locked');

    // Fresh app on the same storage.
    await tester.pumpWidget(const SizedBox());
    await openVault(tester, store: store);
    expect(find.text('287 082'), findsOneWidget);
  });

  testWidgets('unreadable saved accounts are reported, not wiped', (tester) async {
    final store = await storeWithPin('482913');
    store.values['vaultline.accounts.v1'] = '{corrupt';
    await openVault(tester, store: store);
    expect(find.text('Couldn’t read your accounts'), findsOneWidget);
    expect(store.values['vaultline.accounts.v1'], '{corrupt');
  });
}
