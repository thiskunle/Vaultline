// On-device QR check: draws a real otpauth:// QR code to a PNG, decodes it
// with the platform decoder (Apple Vision / bundled ML Kit), then runs the
// full "Choose image" flow with only the photo picker stubbed. Finally opens
// the live scanner and holds it so the host can capture the device screen
// (camera previews are platform views that Flutter screenshots can't see).
//
//   TOUR_PLATFORM=ios flutter drive --driver=tool/device_tour/driver.dart \
//     --target=tool/device_tour/scan_test.dart -d "iPhone 18 Pro"
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qr/qr.dart';
import 'package:vaultline/app.dart';
import 'package:vaultline/providers/vault_providers.dart';
import 'package:vaultline/security/lock_service.dart';
import 'package:vaultline/security/qr_sources.dart';
import 'package:vaultline/security/secure_store.dart';

const uri = 'otpauth://totp/GitHub:ada%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';

class _StubReader implements QrImageReader {
  _StubReader(this.value);
  final String value;
  @override
  Future<String?> read(String path) async => value;
}

class StubPicker implements ImageSourcePicker {
  StubPicker(this.path);
  final String path;
  @override
  Future<String?> pickImagePath() async => path;
}

/// Renders [data] as a QR code PNG (with a quiet zone) and returns its path.
Future<String> writeQrPng(String data) async {
  final image = QrImage(QrCode(payload: QrPayload.fromString(data)));
  const scale = 12.0;
  const quiet = 4;
  final size = (image.moduleCount + quiet * 2) * scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawRect(Rect.fromLTWH(0, 0, size, size), Paint()..color = Colors.white);
  final black = Paint()..color = Colors.black;
  for (var r = 0; r < image.moduleCount; r++) {
    for (var c = 0; c < image.moduleCount; c++) {
      if (image.isDark(r, c)) {
        canvas.drawRect(Rect.fromLTWH((c + quiet) * scale, (r + quiet) * scale, scale, scale), black);
      }
    }
  }
  final png = await (await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  )).toByteData(format: ui.ImageByteFormat.png);
  final file = File('${Directory.systemTemp.path}/vaultline_test_qr.png');
  await file.writeAsBytes(png!.buffer.asUint8List());
  return file.path;
}

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

  testWidgets('QR decode and scan flows on device', (tester) async {
    final path = await writeQrPng(uri);
    // The plugin can't analyse image files on the iOS Simulator (real iPhones
    // and Android can). Report that honestly and stub only the decoder there,
    // so the rest of the flow still runs.
    var platformDecodes = true;
    try {
      final decoded = await PlatformQrImageReader().read(path);
      // ignore: avoid_print
      print('PLATFORM_DECODE ${decoded == uri ? 'OK' : 'MISMATCH: $decoded'}');
      expect(decoded, uri);
    } on UnsupportedError {
      platformDecodes = false;
      // ignore: avoid_print
      print('PLATFORM_DECODE UNSUPPORTED on this device (decoder stubbed for the UI flow)');
    }

    final store = MemorySecureStore();
    await LockService(store: store).setPin('482913');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStoreProvider.overrideWithValue(store),
          imagePickerProvider.overrideWithValue(StubPicker(path)),
          if (!platformDecodes) qrImageReaderProvider.overrideWithValue(_StubReader(uri)),
        ],
        child: const VaultlineApp(),
      ),
    );
    await wait(tester, const Duration(seconds: 1));
    for (final d in '482913'.split('')) {
      await tester.tap(find.byKey(Key('key-$d')));
      await wait(tester, const Duration(milliseconds: 90));
    }
    await wait(tester, const Duration(seconds: 4));

    // Choose image → real decoder → pre-filled form.
    await tester.tap(find.byKey(const Key('add-first-account')));
    await wait(tester, const Duration(milliseconds: 700));
    await shot(tester, '20_add_methods');
    await tester.tap(find.byKey(const Key('add-via-image')));
    await wait(tester, const Duration(seconds: 2));
    expect(find.text('Check and add'), findsOneWidget);
    await shot(tester, '21_check_and_add');
    await tester.ensureVisible(find.byKey(const Key('save-account')));
    await wait(tester, const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('save-account')));
    await wait(tester, const Duration(seconds: 1));
    expect(find.text('GitHub'), findsOneWidget);

    // Live scanner with the real camera.
    await tester.tap(find.byKey(const Key('add-account')));
    await wait(tester, const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const Key('add-via-scan')));
    await wait(tester, const Duration(seconds: 4));
    await shot(tester, '22_scanner');
    // ignore: avoid_print
    print('SCANNER_OPEN camera-error=${find.byKey(const Key('camera-error')).evaluate().isNotEmpty}');
    await wait(tester, const Duration(seconds: 12));
  });
}
