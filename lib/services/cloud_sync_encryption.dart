import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudSyncEncryption {
  const CloudSyncEncryption._();

  static const format = 'streak-drive-encrypted';
  static const version = 1;
  static const _iterations = 120000;
  static const _passphraseKey = 'streak.drive.sync.passphrase';
  static const _storage = FlutterSecureStorage();

  static Future<String?> savedPassphrase() =>
      _storage.read(key: _passphraseKey);

  static Future<void> savePassphrase(String passphrase) => _storage.write(
        key: _passphraseKey,
        value: passphrase,
      );

  static Future<String> encrypt(String plaintext, String passphrase) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return json.encode({
      'syncFormat': format,
      'syncVersion': version,
      'kdf': 'pbkdf2-sha256',
      'iterations': _iterations,
      'salt': base64Url.encode(salt),
      'nonce': base64Url.encode(box.nonce),
      'cipherText': base64Url.encode(box.cipherText),
      'mac': base64Url.encode(box.mac.bytes),
    });
  }

  static Future<String> decrypt(String raw, String passphrase) async {
    final value = json.decode(raw);
    if (value is! Map || value['syncFormat'] != format) {
      throw const FormatException('Unrecognised encrypted Drive sync file');
    }
    if (value['syncVersion'] != version || value['kdf'] != 'pbkdf2-sha256') {
      throw const FormatException('Unsupported encrypted Drive sync version');
    }
    if (value['iterations'] != _iterations) {
      throw const FormatException('Unsupported encrypted Drive sync settings');
    }
    List<int> bytes(String key) {
      final encoded = value[key];
      if (encoded is! String) throw const FormatException('Invalid encrypted sync data');
      return base64Url.decode(encoded);
    }

    final salt = bytes('salt');
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    ).deriveKey(
          secretKey: SecretKey(utf8.encode(passphrase)),
          nonce: salt,
        );
    final plaintext = await AesGcm.with256bits().decrypt(
      SecretBox(
        bytes('cipherText'),
        nonce: bytes('nonce'),
        mac: Mac(bytes('mac')),
      ),
      secretKey: key,
    );
    return utf8.decode(plaintext);
  }
}
