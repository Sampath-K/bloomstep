import 'package:flutter/services.dart';

class NativeShare {
  static const _channel = MethodChannel('bloomstep/native_share');

  static Future<void> share(Uri url) async {
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.toString().length > 2048) {
      throw const FormatException(
        'Only a safe HTTPS invitation can be shared.',
      );
    }
    await _channel.invokeMethod<void>('share', {
      'url': url.toString(),
      'title': 'A little is enough',
      'description':
          'Grow a tiny habit with Bloomstep. No private garden data is shared.',
    });
  }
}
