import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultline/security/lock_service.dart';
import 'package:vaultline/security/pin_hasher.dart';
import 'package:vaultline/security/secure_store.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    test('matches a published test vector (RFC 7914 §11)', () async {
      // P="passwd", S="salt", c=1, dkLen=64
      final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 1, bits: 512);
      final key = await pbkdf2.deriveKeyFromPassword(password: 'passwd', nonce: utf8.encode('salt'));
      expect(
        hex(await key.extractBytes()),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('verifies the right PIN only, with a random salt per PIN', () async {
      const hasher = PinHasher(iterations: 1000);
      final a = await hasher.create('482913');
      final b = await hasher.create('482913');
      expect(await hasher.verify('482913', a), isTrue);
      expect(await hasher.verify('482914', a), isFalse);
      expect(a.salt, isNot(equals(b.salt)), reason: 'salts must be random');
      expect(a.hash, isNot(equals(b.hash)));
    });

    test('record round-trips and never contains the PIN', () async {
      final record = await const PinHasher(iterations: 1000).create('482913');
      final raw = record.encode();
      expect(raw, isNot(contains('482913')));
      final back = PinRecord.decode(raw);
      expect(back.iterations, 1000);
      expect(await const PinHasher().verify('482913', back), isTrue);
    });

    test('constant-time compare', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
    });
  });

  group('PIN rules', () {
    test('six digits only', () {
      expect(LockService.isValidPin('123456'), isTrue);
      expect(LockService.isValidPin('12345'), isFalse);
      expect(LockService.isValidPin('12345a'), isFalse);
    });

    test('rejects trivially guessable PINs', () {
      for (final weak in ['000000', '111111', '123456', '654321', '345678', '987654']) {
        expect(LockService.isWeakPin(weak), isTrue, reason: weak);
      }
      for (final ok in ['482913', '190274', '135792']) {
        expect(LockService.isWeakPin(ok), isFalse, reason: ok);
      }
    });
  });

  group('LockService', () {
    late DateTime now;
    late MemorySecureStore store;
    LockService service() => LockService(store: store, hasher: const PinHasher(iterations: 1000), clock: () => now);

    setUp(() {
      now = DateTime(2026, 11, 8, 9);
      store = MemorySecureStore();
    });

    test('setup, then unlock with the right PIN', () async {
      expect(await service().hasPin(), isFalse);
      await service().setPin('482913');
      expect(await service().hasPin(), isTrue);
      expect(await service().unlockWithPin('482913'), isA<Unlocked>());
    });

    test('5 wrong PINs lock for 30 s, then the wait doubles up to 15 min', () async {
      await service().setPin('482913');
      for (var left = 4; left >= 1; left--) {
        final r = await service().unlockWithPin('000001');
        expect(r, isA<WrongPin>());
        expect((r as WrongPin).attemptsBeforeLockout, left);
      }
      var r = await service().unlockWithPin('000001');
      expect(r, isA<LockedOut>());
      expect((r as LockedOut).until, now.add(const Duration(seconds: 30)));

      // Even the right PIN is refused during a lockout.
      expect(await service().unlockWithPin('482913'), isA<LockedOut>());

      final waits = <int>[];
      for (var i = 0; i < 8; i++) {
        now = (await service().lockedUntil())!.add(const Duration(seconds: 1));
        r = await service().unlockWithPin('000001');
        waits.add((r as LockedOut).until.difference(now).inSeconds);
      }
      expect(waits, [60, 120, 240, 480, 900, 900, 900, 900]);
    });

    test('the right PIN after a lockout expires resets the counter', () async {
      await service().setPin('482913');
      for (var i = 0; i < 5; i++) {
        await service().unlockWithPin('000001');
      }
      now = now.add(const Duration(seconds: 31));
      expect(await service().unlockWithPin('482913'), isA<Unlocked>());
      final r = await service().unlockWithPin('000001');
      expect((r as WrongPin).attemptsBeforeLockout, 4);
    });

    test('lockout survives a restart (new service, same storage)', () async {
      await service().setPin('482913');
      for (var i = 0; i < 5; i++) {
        await service().unlockWithPin('000001');
      }
      final restarted = service();
      expect(await restarted.lockedUntil(), isNotNull);
      expect(await restarted.unlockWithPin('482913'), isA<LockedOut>());
    });

    test('tampered failure counter is treated cautiously, not reset', () async {
      await service().setPin('482913');
      store.values['vaultline.failures.v1'] = 'garbage';
      final r = await service().unlockWithPin('000001');
      expect(r, isA<LockedOut>());
    });

    test('biometric preference is stored and can be turned off', () async {
      expect(await service().biometricEnabled(), isFalse);
      await service().setBiometricEnabled(true);
      expect(await service().biometricEnabled(), isTrue);
      await service().setBiometricEnabled(false);
      expect(await service().biometricEnabled(), isFalse);
    });
  });
}
