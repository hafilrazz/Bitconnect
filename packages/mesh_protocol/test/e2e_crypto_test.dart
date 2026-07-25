import 'package:mesh_protocol/mesh_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('E2E seal/open roundtrip + wrong recipient fails', () async {
    final senderSign = await CryptoIdentity.generate();
    final senderEnc = await EncryptionIdentity.generate();
    final recipientEnc = await EncryptionIdentity.generate();
    final otherEnc = await EncryptionIdentity.generate();

    final sealed = await E2eBox.seal(
      senderSign: senderSign,
      senderEnc: senderEnc,
      recipientX25519Pk: recipientEnc.publicKeyBytes,
      plaintext: 'hello from India to USA',
      nickname: 'alice',
    );

    final opened = await E2eBox.open(
      recipientEnc: recipientEnc,
      sealed: sealed,
    );
    expect(opened.plaintext, 'hello from India to USA');
    expect(opened.nickname, 'alice');

    // JSON wire format
    final again = E2eSealedMessage.decode(sealed.encode());
    final opened2 = await E2eBox.open(recipientEnc: recipientEnc, sealed: again);
    expect(opened2.plaintext, 'hello from India to USA');

    await expectLater(
      () => E2eBox.open(recipientEnc: otherEnc, sealed: sealed),
      throwsA(isA<StateError>()),
    );
  });

  test('tampered ciphertext rejected', () async {
    final senderSign = await CryptoIdentity.generate();
    final senderEnc = await EncryptionIdentity.generate();
    final recipientEnc = await EncryptionIdentity.generate();
    final sealed = await E2eBox.seal(
      senderSign: senderSign,
      senderEnc: senderEnc,
      recipientX25519Pk: recipientEnc.publicKeyBytes,
      plaintext: 'secret',
    );
    sealed.ciphertext[0] ^= 0xff;
    await expectLater(
      () => E2eBox.open(recipientEnc: recipientEnc, sealed: sealed),
      throwsA(anything),
    );
  });
}
