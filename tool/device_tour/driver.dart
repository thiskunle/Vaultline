// Host side of the device tour: saves screenshots to
// build/device_tour/<platform>/<name>.png.
//
//   TOUR_PLATFORM=ios flutter drive --driver=tool/device_tour/driver.dart \
//     --target=tool/device_tour/tour_test.dart -d "iPhone 18 Pro"
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() {
  final platform = Platform.environment['TOUR_PLATFORM'] ?? 'device';
  return integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      File('build/device_tour/$platform/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      return true;
    },
  );
}
