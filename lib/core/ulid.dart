import 'dart:math';

/// ULID (26 Crockford base-32 chars: 48-bit time + 80-bit randomness), the id
/// format the server uses. Records created offline get their final id on the
/// phone, so later operations in the queue can point to them.
abstract final class Ulid {
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final _random = Random.secure();

  static String generate({DateTime? at}) {
    var time = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final chars = List.filled(26, '0');
    for (var i = 9; i >= 0; i--) {
      chars[i] = _alphabet[time % 32];
      time ~/= 32;
    }
    for (var i = 10; i < 26; i++) {
      chars[i] = _alphabet[_random.nextInt(32)];
    }
    return chars.join();
  }
}
