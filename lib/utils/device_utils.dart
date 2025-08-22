import 'package:device_info_plus/device_info_plus.dart';

class DeviceUtils {
  static Future<String> getDeviceId() async {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.id ?? info.androidId ?? 'unknown_device';
  }
}
