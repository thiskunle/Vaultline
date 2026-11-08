import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../otp/otpauth_uri.dart';
import '../providers/vault_providers.dart';
import '../routing/app_router.dart';
import '../theme/app_theme.dart';

/// Parses scanned text and, if it's a 2FA setup code, opens the Add account
/// screen pre-filled for review. Returns an error message otherwise.
String? openScannedCode(BuildContext context, WidgetRef ref, String raw, {bool replace = false}) {
  try {
    final account = OtpAuthUri.parse(raw, id: AccountsController.newId(), now: ref.read(clockProvider)());
    HapticFeedback.mediumImpact();
    if (replace) {
      context.pushReplacement(Routes.addAccount, extra: account);
    } else {
      context.push(Routes.addAccount, extra: account);
    }
    return null;
  } on OtpUriException catch (e) {
    return e.message;
  }
}

/// Reads a QR code from an image in the photo library.
Future<void> addFromImage(BuildContext context, WidgetRef ref, {bool replace = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  final path = await ref.read(imagePickerProvider).pickImagePath();
  if (path == null || !context.mounted) return;
  String? raw;
  try {
    raw = await ref.read(qrImageReaderProvider).read(path);
  } on UnsupportedError {
    // e.g. the iOS Simulator, where the plugin can't analyse image files.
    if (context.mounted) {
      say('Reading QR codes from images isn’t available on this device. Scan with the camera or enter the key.');
    }
    return;
  } catch (_) {
    if (context.mounted) say('Couldn’t read that image.');
    return;
  }
  if (!context.mounted) return;
  if (raw == null) {
    say('No QR code found in that image.');
    return;
  }
  final error = openScannedCode(context, ref, raw, replace: replace);
  if (error != null) say(error);
}

/// Bottom sheet: scan, choose an image, or type the key.
Future<void> showAddMethods(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: VColors.surface,
    showDragHandle: true,
    builder: (context) {
      Widget tile(String id, IconData icon, String title, String subtitle) => ListTile(
        key: Key('add-via-$id'),
        leading: Icon(icon, color: VColors.accent),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: () => Navigator.pop(context, id),
      );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile('scan', Icons.qr_code_scanner_rounded, 'Scan QR code', 'Point the camera at the code'),
            tile('image', Icons.image_outlined, 'Choose image', 'Read a QR code from a screenshot'),
            tile('key', Icons.keyboard_alt_outlined, 'Enter setup key', 'Type or paste the key'),
          ],
        ),
      );
    },
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'scan':
      await context.push(Routes.scan);
    case 'image':
      await addFromImage(context, ref);
    case 'key':
      await context.push(Routes.addAccount);
  }
}
