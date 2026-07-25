# Netless mesh protocol v1

Application-level BLE gossip. Not Bluetooth SIG Mesh.

## Packet layout

All multi-byte integers are **big-endian**.

| Field | Size | Notes |
|---|---|---|
| magic | 2 | 0x4E54 (NT) |
| version | 1 | 1 |
| type | 1 | 1=CHAT, 2=ANNOUNCE |
| ttl | 1 | hops remaining |
| flags | 1 | reserved 0 |
| channel_id | 2 | #local = 1 |
| msg_id | 16 | random UUID bytes |
| sender_pk | 32 | Ed25519 public key |
| timestamp | 4 | Unix seconds |
| nickname_len | 1 | 0-24 |
| nickname | N | UTF-8 |
| body_len | 2 | 0-200 for MVP |
| body | M | UTF-8 |
| signature | 64 | Ed25519 over sign payload |

### Sign payload

```
version || type || channel_id || msg_id || sender_pk || timestamp || nickname_bytes || body
```

## Gossip rules

1. Create: TTL = MAX_TTL (7), new msg_id, sign, store, send to all peers.
2. Receive: drop bad magic/version, duplicates, bad signature, timestamp skew; else deliver and forward with ttl-1.

## Limits

- Nickname <= 24 UTF-8 bytes
- Body <= 200 UTF-8 bytes
- Default max TTL = 7
