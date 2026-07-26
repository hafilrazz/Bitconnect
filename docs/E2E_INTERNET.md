# Internet E2E messaging (Bitconnect)

## Threat model

- **Relays are untrusted.** Public Nostr relays only store ciphertext.
- **Plaintext is sealed on-device** with X25519 ECDH + ChaCha20-Poly1305.
- **Sender authenticity** via Ed25519 signature over the sealed fields.
- **Bitconnect ID** = recipient’s static X25519 public key (64 hex chars).

## What is end-to-end

Only the intended recipient’s private X25519 key can open the box.  
India ↔ USA works when **both phones have internet**.

## What is not private

- Metadata: that *someone* sent a Bitconnect event at time T (relay sees size/time/tags).
- Your Bitconnect ID is a public address (like a phone number for crypto).

## How to use

1. Open **Worldwide E2E** (bottom nav).
2. Copy **your Bitconnect ID** and send it out-of-band (QR, SMS, etc.).
3. Paste their Bitconnect ID → **Save & chat**.
4. Connect (cloud) and send. Messages show a lock icon.

## Wire format

Nostr `kind: 21000` event:

- `tags`: `[["p", "<recipient_x25519_hex>"], ["netless", "e2e-v1"]]`  
  (tag value `netless` is a stable protocol marker, not the product name)
- `content`: JSON sealed box (`v,ssp,sep,rep,eph,ts,nick,nonce,ct,sig`)

Outer Nostr signature is only for relay acceptance. Real confidentiality/authenticity is the sealed box.
