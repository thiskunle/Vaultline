import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vaultline/providers/vault_providers.dart';
import 'package:vaultline/security/qr_sources.dart';

import '../helpers.dart';

const githubQr = 'otpauth://totp/GitHub:ada%40example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=GitHub';

/// Stands in for the camera: tests call [emit] as if a QR code came into view.
class FakeCamera {
  ValueChanged<String>? _onCode;
  MobileScannerException? failWith;

  void emit(String raw) => _onCode!(raw);

  QrCameraBuilder get builder => ({required onCode, required controller, required error}) {
    _onCode = onCode;
    final fail = failWith;
    return fail == null ? const ColoredBox(color: Colors.black) : Builder(builder: (context) => error(context, fail));
  };
}

class FakePicker implements ImageSourcePicker {
  FakePicker(this.path);
  final String? path;
  @override
  Future<String?> pickImagePath() async => path;
}

class FakeReader implements QrImageReader {
  FakeReader(this.result, {this.unsupported = false});
  final String? result;
  final bool unsupported;
  @override
  Future<String?> read(String path) async {
    if (unsupported) throw UnsupportedError('not on this device');
    return result;
  }
}

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);

  Future<FakeCamera> openVault(
    WidgetTester tester, {
    FakeCamera? camera,
    String? pickedPath = '/photos/qr.png',
    String? decoded,
    bool readerUnsupported = false,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    final cam = camera ?? FakeCamera();
    await launch(
      tester,
      await storeWithPin('482913'),
      clock: () => now,
      overrides: [
        qrCameraProvider.overrideWithValue(cam.builder),
        imagePickerProvider.overrideWithValue(FakePicker(pickedPath)),
        qrImageReaderProvider.overrideWithValue(FakeReader(decoded, unsupported: readerUnsupported)),
      ],
    );
    await typePin(tester, '482913');
    await settle(tester, steps: 30);
    return cam;
  }

  Future<void> choose(WidgetTester tester, String method) async {
    await tester.tap(find.byKey(const Key('add-first-account')));
    await settle(tester, steps: 5);
    await tester.tap(find.byKey(Key('add-via-$method')));
    await settle(tester);
  }

  String fieldText(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('scanning a setup QR opens a pre-filled form to check, then adds it', (tester) async {
    final cam = await openVault(tester);
    await choose(tester, 'scan');
    expect(find.text('Scan QR code'), findsOneWidget);

    cam.emit(githubQr);
    await settle(tester);
    expect(find.text('Check and add'), findsOneWidget);
    expect(fieldText(tester, 'field-issuer'), 'GitHub');
    expect(fieldText(tester, 'field-name'), 'ada@example.com');
    expect(fieldText(tester, 'field-secret'), 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
    expect(find.text('287 082'), findsOneWidget, reason: 'live preview');

    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await settle(tester, steps: 3);
    await tester.tap(find.byKey(const Key('save-account')));
    await settle(tester);
    // Back on the list (the scanner was replaced, not stacked).
    expect(find.text('Authenticator'), findsOneWidget);
    expect(find.text('287 082'), findsOneWidget);
  });

  testWidgets('non-2FA and unsupported codes are explained, and scanning continues', (tester) async {
    final cam = await openVault(tester);
    await choose(tester, 'scan');

    cam.emit('https://example.com/menu');
    await settle(tester, steps: 5);
    expect(find.text('That QR code isn’t a 2FA setup code.'), findsOneWidget);

    cam.emit('otpauth://hotp/x?secret=JBSWY3DPEHPK3PXP&counter=1');
    await settle(tester, steps: 5);
    expect(find.textContaining('HOTP'), findsOneWidget);
    expect(find.text('Scan QR code'), findsOneWidget, reason: 'still scanning');

    cam.emit(githubQr);
    await settle(tester);
    expect(find.text('Check and add'), findsOneWidget);
  });

  testWidgets('choose image: found, not found, and cancelled', (tester) async {
    await openVault(tester, decoded: githubQr);
    await choose(tester, 'image');
    expect(find.text('Check and add'), findsOneWidget);
    expect(fieldText(tester, 'field-issuer'), 'GitHub');
  });

  testWidgets('choose image with no QR code in it', (tester) async {
    await openVault(tester, decoded: null);
    await choose(tester, 'image');
    expect(find.text('No QR code found in that image.'), findsOneWidget);
    expect(find.text('Authenticator'), findsOneWidget);
  });

  testWidgets('devices that can’t read images say so (not "no QR code found")', (tester) async {
    await openVault(tester, decoded: githubQr, readerUnsupported: true);
    await choose(tester, 'image');
    expect(find.textContaining('isn’t available on this device'), findsOneWidget);
    expect(find.text('No QR code found in that image.'), findsNothing);
  });

  testWidgets('cancelling the photo picker changes nothing', (tester) async {
    await openVault(tester, pickedPath: null, decoded: githubQr);
    await choose(tester, 'image');
    expect(find.text('Check and add'), findsNothing);
    expect(find.text('No accounts yet'), findsOneWidget);
  });

  testWidgets('camera permission denied: clear message and other ways in', (tester) async {
    final cam = FakeCamera()
      ..failWith = const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied);
    await openVault(tester, camera: cam);
    await choose(tester, 'scan');
    expect(find.textContaining('Camera access is off for Vaultline'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-enter-key')));
    await settle(tester);
    expect(find.text('Add account'), findsOneWidget);
  });
}
