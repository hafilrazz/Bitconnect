# Demo guide (Bitconnect)

## Range tips (local mesh)

- Keep **Bitconnect open** (foreground) on all phones.
- High advertise TX + aggressive scan are enabled in software; walls/bodies still block BLE.
- **More phones between A and C** extends reach more than TX power alone.
- Line of sight outdoors usually beats indoor multi-room.

## Two phones (single hop)

1. Install on phone A and B.
2. Enable Bluetooth. Open **Bitconnect**, set nicknames.
3. **Local mesh** → Start mesh on both; wait for peer count ≥ 1.
4. Send on #local from A; B should show it.

## Three phones (multi-hop)

Topology A -- B -- C with A and C not direct peers.

1. Space A and C far apart; B mid-path.
2. Mesh on all three.
3. A sends hop test; C receives via B.

## Worldwide E2E

1. Both phones online.
2. Exchange Bitconnect IDs on **Worldwide**.
3. Connect relays and send a locked message.

## Acceptance

- [ ] Works in airplane mode (local mesh only)
- [ ] Invalid signatures never appear
- [ ] No duplicate msg_id in timeline
- [ ] Multi-hop observed at least once
- [ ] India ↔ USA style E2E works with internet
