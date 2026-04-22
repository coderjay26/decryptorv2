import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class Decryptor {
  final encrypt.Key _key;

  Decryptor(String key32Bytes) : _key = encrypt.Key.fromUtf8(key32Bytes);

  String decryptWithIvPrefix(Uint8List data) {
    if (data.length < 16) throw Exception("Invalid data, too short");

    final ivBytes = data.sublist(0, 16);
    final cipherBytes = data.sublist(16);

    final iv = encrypt.IV(ivBytes);
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));

    final encrypted = encrypt.Encrypted(cipherBytes);
    return encrypter.decrypt(encrypted, iv: iv);
  }

  Uint8List decryptBytesWithIvPrefix(Uint8List data) {
    print('Data length: ${data.length} bytes');

    if (data.length < 16) throw Exception("Invalid data, too short");

    final ivBytes = data.sublist(0, 16);
    final cipherBytes = data.sublist(16);

    print('IV bytes: ${ivBytes.length}, Cipher bytes: ${cipherBytes.length}');

    final iv = encrypt.IV(ivBytes);
    final encrypter =
        encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypt.Encrypted(cipherBytes);

    print('Starting decryption...');
    final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
    print('Decryption completed: ${decrypted.length} bytes');

    return Uint8List.fromList(decrypted);
  }

  String decryptBytesWithIvPrefixNew(Uint8List data) {
    print('Data length: ${data.length} bytes');

    if (data.length < 16) throw Exception("Invalid data, too short");

    final ivBytes = data.sublist(0, 16);
    final cipherBytes = data.sublist(16);

    print('IV bytes: ${ivBytes.length}, Cipher bytes: ${cipherBytes.length}');

    final iv = encrypt.IV(ivBytes);
    final encrypter =
        encrypt.Encrypter(encrypt.AES(_key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypt.Encrypted(cipherBytes);

    print('Starting decryption...');
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    print('Decryption completed: ${decrypted.length} bytes');

    return decrypted;
  }
}
