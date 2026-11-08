import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Picks an image from the photo library. Null if the person cancels.
abstract interface class ImageSourcePicker {
  Future<String?> pickImagePath();
}

class PlatformImagePicker implements ImageSourcePicker {
  @override
  Future<String?> pickImagePath() async => (await ImagePicker().pickImage(source: ImageSource.gallery))?.path;
}

/// Finds QR codes in an image file, on the device (Vision on iOS, bundled
/// ML Kit on Android). Images are never uploaded.
abstract interface class QrImageReader {
  /// The text of the first QR code in the image, or null if there is none.
  Future<String?> read(String path);
}

class PlatformQrImageReader implements QrImageReader {
  @override
  Future<String?> read(String path) async {
    final controller = MobileScannerController(autoStart: false, formats: const [BarcodeFormat.qrCode]);
    try {
      final capture = await controller.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
      return capture?.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    } finally {
      await controller.dispose();
    }
  }
}

/// Builds the live camera view. [onCode] receives decoded QR text; [error]
/// builds the message shown when the camera can't be used.
typedef QrCameraBuilder = Widget Function({
  required ValueChanged<String> onCode,
  required MobileScannerController controller,
  required Widget Function(BuildContext, MobileScannerException) error,
});

Widget platformQrCamera({
  required ValueChanged<String> onCode,
  required MobileScannerController controller,
  required Widget Function(BuildContext, MobileScannerException) error,
}) => MobileScanner(
  controller: controller,
  errorBuilder: error,
  onDetect: (capture) {
    final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (value != null) onCode(value);
  },
);
