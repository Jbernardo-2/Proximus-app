import 'package:flutter/services.dart';

/// Dialer, WhatsApp and maps through Android intents (no extra package).
abstract final class ExternalApps {
  static const _channel = MethodChannel('proximus/external');

  static Future<bool> _open(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('open', {'uri': uri}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> call(String phone) => _open('tel:${_digits(phone, keepPlus: true)}');

  /// Honduran numbers of 8 digits get the 504 country code, as on the web.
  static Future<bool> whatsapp(String phone, {String? text}) {
    var digits = _digits(phone);
    if (digits.length == 8) digits = '504$digits';
    final message = text == null ? '' : '?text=${Uri.encodeComponent(text)}';
    return _open('https://wa.me/$digits$message');
  }

  /// Opens the maps app on the point; with no coordinates, searches the address.
  static Future<bool> map({String? latitude, String? longitude, required String label}) {
    if (latitude != null && longitude != null) {
      return _open('geo:$latitude,$longitude?q=$latitude,$longitude(${Uri.encodeComponent(label)})');
    }
    return _open('geo:0,0?q=${Uri.encodeComponent(label)}');
  }

  /// Whether Android lets the app use the network with the screen off and power saving
  /// on. Null when it cannot tell (tests, other platforms).
  static Future<bool?> isBackgroundAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('isBackgroundAllowed');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Asks the user to let Proximus work without battery restrictions.
  static Future<bool> requestBackground() async {
    try {
      return await _channel.invokeMethod<bool>('requestBackground') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static String _digits(String value, {bool keepPlus = false}) =>
      value.replaceAll(RegExp(keepPlus ? r'[^\d+]' : r'\D'), '');
}
