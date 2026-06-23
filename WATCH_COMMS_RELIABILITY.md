# Watch↔Phone Communication Reliability

The reliability pattern behind SundialKitStream's **`ContextEngine`** — how two
peers stay in sync dependably over WatchConnectivity, and how to debug the link.
`ContextEngine` (with `RevisionedMessage` / `ExpiringMessage` / `StaleWindow`)
productizes everything described here; **AtLeast** is the worked example
referenced throughout, with `SessionIntent` (phone→watch) and `TimerStateUpdate`
(watch→phone) as the concrete payloads.

---

## The transport: one latest-wins slot per direction

All traffic rides WatchConnectivity **application context** through our owned
`SundialKitStream`. Application context is a **single dictionary per direction**,
latest-wins: a new value overwrites any undelivered previous one, and — critically
— **WCSession never delivers a context byte-identical to the one before it.**
`MessageDistributor.handleApplicationContext` enforces the same dedup on receive
(canonical-JSON equality).

This is the right transport for *latest-desired-state* messaging, but three things
made it flaky when it was used like a reliable queue:

1. **`TimerStateUpdate` (watch→phone) had no uniqueness token.** A re-asserted
   state equal to the last one was silently dropped — so the watch's reconnect
   re-assert never reached the phone and the mirror got stuck.
2. **Discrete commands shared the phone's one slot.** A `StartTimerCommand`
   followed by a `RequestStateCommand` overwrote the start before delivery; the
   code papered over this with a `phase != .starting` guard.
3. **Nothing re-asserted.** A single dropped/coalesced delivery never self-healed.

## The design

### 1. Monotonic `revision` on every message
Both `TimerStateUpdate` and `SessionIntent` carry a `revision: UInt64` that the
sender bumps on **every** send (change-driven and heartbeat). This guarantees each
context differs, so neither WCSession nor the receive-side dedup can silently drop
a re-assert. `revision` is **not** used to gate application on the receiver — it
resets when the sender relaunches, so gating would wrongly drop a fresh session.
It is purely a transport-uniqueness / correlation token.

### 2. Intent snapshot (phone→watch), applied idempotently
The phone never sends discrete commands. It holds one **`SessionIntent`**
(`kind: .none/.start/.stop`, optional `configuration`, `revision`, `sentAt`) and
always writes its *complete* desired intent to its outbound slot — so a start can't
be clobbered by a following request (there's nothing to lose). The discrete
`StartTimerCommand`/`StopTimerCommand`/`RequestStateCommand`/`TimestampedCommand`
and `IncomingCommandFilter` were retired.

The watch reconciles via **`IntentReconciler`** (a pure function of intent + now):
it drops only snapshots older than a stale window (~30 s) — so a parked `.start`
replayed at next launch can't begin a timer — and returns a desired `Outcome`. The
watch applies it **idempotently** against current state: `.start` is a no-op when
already running, `.stop` a no-op when idle. Combined with latest-wins coalescing,
repeated/re-asserted intents converge on the user's most recent wish.

The watch stamps `startTime` **at apply time** (matches the "at least" concept;
avoids waking into a mostly-elapsed session). On any inbound intent the watch also
re-asserts its current state, so the phone (re)syncs on every contact, including a
fresh launch.

### 3. Heartbeat self-heal (~3 s)
- **Watch** (`ConnectivityService`, on the lifetime service — not a view `.task`):
  re-asserts `TimerStateUpdate` every `heartbeatInterval` while running.
- **Phone** (`SessionController`): re-asserts the current `SessionIntent` while a
  session is presented.

Because application context coalesces, heartbeats are cheap (only the latest
matters); the `revision` is what makes each one actually deliver. Any single missed
update self-heals within one interval. The phone still keeps its 10 s `.starting`
spinner timeout; idempotent application means a late landing starts exactly one
timer.

## Structured logging trace

`SundialKitStream` emits a structured `StreamLogEvent` (kind + key/value fields),
which `AppLog.installSundialBridge()` maps onto Broadcast `Log.Signal`/`Log.Payload`
under the `Connectivity` category. The dedup-skip site logs `dropped`/`reason=dedup`
with the message type — the silent-drop site is now visible.

Debug loop: `make logs` streams both devices (token-optimized stdout). Trace one
message end-to-end by its correlation token: `grep "p.revision=7"` across
`logs/*-watch.log` and `logs/*-iphone.log`; a gap shows exactly where a chain broke.
Signals: send=`.action`, delivered/received=`.event`, dropped/dedup=`.diagnostic`,
heartbeat=`.metric`, reachability=`.state`.

## Key files
- `Packages/AtLeastKit/Sources/AtLeastKit/TimerStateUpdate.swift` — `revision`
- `Packages/AtLeastKit/Sources/AtLeastKit/SessionIntent.swift` — intent snapshot
- `Packages/AtLeastKit/Sources/AtLeastKit/IntentReconciler.swift` — reconcile + stale window
- `Packages/AtLeastKit/Sources/AtLeastApp/SessionController.swift` — phone intent + heartbeat
- `Packages/AtLeastKit/Sources/AtLeastApp/ConnectivityService.swift` — watch reconcile, heartbeat, reporting
- `Packages/AtLeastKit/Sources/AtLeastApp/WatchRootView.swift` — idempotent apply, state provider
- `Packages/AtLeastKit/Sources/AtLeastApp/AppLog.swift` — structured bridge + payload vocabulary
- `Packages/SundialKitStream/Sources/SundialKitStream/SundialStreamLog.Event.swift` — structured event

## Regression tests
`IntentReconcilerTests`, `RevisionUniquenessTests` (the dedup-defeat guarantee:
same-content messages with different revisions encode to distinct dictionaries),
`MessagableCodableTests`, `MessagableEnvelopeDecodeTests`.

## Not covered (deferred)
- Cross-launch persisted logs (`MultiSessionLogger`) on watchOS — see Broadcast's
  `WATCHOS_SUPPORT.md`.
- Foreground remote-start from the phone (queued start) — AtLeast#191.

## Glossary

| Term | Definition |
|------|------------|
| **`ContextEngine<Outbound, Inbound>`** | The engine: owns the revision counter, heartbeat re-assert, reachability/installed state, reassert-on-reconnect, and reply-on-inbound. The app supplies `makeOutbound` / `onInbound` / `shouldReassert`. |
| **`RevisionedMessage`** | A payload carrying a monotonic `revision: UInt64`, bumped on every send so each application context is distinct and dedup can't drop a re-assert. A transport-uniqueness / log-correlation token, not a receive-side gate. |
| **`ExpiringMessage`** | A `RevisionedMessage` that also carries `sentAt`, so a snapshot replayed into a fresh launch can be dropped once it's too old to act on. |
| **`StaleWindow`** | Decides whether an `ExpiringMessage` is recent enough to act on (default ~30 s) — e.g. a parked `.start` replayed at relaunch can't begin a session. |
| **Heartbeat** | A ~3 s re-assert of the latest context on each side so a single dropped or coalesced delivery self-heals. Cheap because application context coalesces. |
| **Idempotent apply** | The receiver treats a snapshot as "ensure this state" (a `.start` is a no-op if already running), so re-asserted/heartbeat-repeated snapshots never disturb a live session. |
| **Reply-on-inbound** | A responder (e.g. the watch) re-asserts its own state after every received snapshot, so the peer re-syncs on every contact. |
