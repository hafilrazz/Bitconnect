# Demo guide

## Two phones (single hop)

1. Install on phone A and B.
2. Enable Bluetooth. Open Netless, set nicknames.
3. Turn Mesh On on both; wait for peer count >= 1.
4. Send on #local from A; B should show it.

## Three phones (multi-hop)

Topology A -- B -- C with A and C not direct peers.

1. Space A and C far apart; B mid-path.
2. Mesh on all three.
3. A sends hop test; C receives via B.

## Acceptance

- [ ] Works in airplane mode
- [ ] Invalid signatures never appear
- [ ] No duplicate msg_id in timeline
- [ ] Multi-hop observed at least once
