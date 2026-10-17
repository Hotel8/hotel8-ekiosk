# Hotel8:eKiosk — Detailed Design Document

## 1. Scope & Context

**Owned by the eKiosk app:**

- The kiosk terminal UX: mode selection (driven by the property's
  `kiosk-config` row), self check-in wizard (identify → summary → add-ons →
  payment → key), self check-out wizard (identify → folio review → payment →
  receipt), walk-in search + express booking, lockdown freeze, and
  boarding-pass/key-collection flow.
- The client-side contract layer (`lib/models.dart`) for kiosk sessions,
  self-service reservations, add-ons, folios, and boarding passes.
- The BFF proxy call surface for the kiosk (`lib/bff_client.dart`).

**Explicitly NOT owned (consuming/delegating):**

| Concern | Owner |
|---|---|
| Reservation lookup, check-in, keys, folio, check-out | Hotel8:PMS (rsv/par/fof/csh) |
| Card authorization + capture | Bill8:Payments (via BFF) |
| Email receipts | Sentin8:Post (via BFF) |
| Add-on/pricing catalog | Hotel8:PMS packages (+ Upsell offers in future) |
| Key-encoding hardware | Kiosk platform channel + vendor SDK (deployment concern) |
| Thermal printing hardware | Kiosk platform channel |
| Payment terminal hardware | Vendor terminal behind the Payments proxy |
| Staff-side kiosk monitoring | Hotel8:ePMS |
| Lockdown mode / kiosk OS | Deployment platform (not the Flutter app) |
| Authorization decision, token custody | Sentin8:Auth + Shield (BFF-guarded, limited-scope) |

### System context

```mermaid
graph TD
    GUEST[Guest at kiosk] -->|"touch UI"| EK[ekiosk app]
    subgraph "trust boundary: eKiosk app process (locked-down terminal)"
        EK[eKiosk Flutter app]
    end
    subgraph "sentin8 platform"
        BFF[Sentin8:BFF /proxy/* limited scope]
        POSTV[Sentin8:Post email receipts]
    end
    subgraph "hotel8 vertical"
        PMS[Hotel8:PMS rsv/par/fof/csh]
    end
    subgraph "bill8 vertical"
        PAY[Bill8:Payments auth + capture]
    end
    HW[Key encoder / thermal printer / payment terminal - platform channel]
    EK -- "no session / limited scope /proxy/*" --> BFF
    BFF -- M2M --> PMS
    BFF -- M2M --> PAY
    BFF -- send receipt --> POSTV
    EK -. platform channel .-> HW
```

### Container view

```mermaid
graph LR
    subgraph "apps/ekiosk (Flutter)"
        MAIN[main.dart] --> SHELL[app.dart HkioskApp]
        SHELL --> HOME[KioskHomePage]
        HOME --> PAGES[wizard screens 4]
        PAGES --> MODELS[models.dart contracts]
        PAGES --> CLIENT[bff_client.dart]
        CLIENT --> MODELS
    end
    CLIENT -- "JSON /proxy/*" --> BFFP[Sentin8:BFF]
    BFFP --> PMSV[Hotel8:PMS]
    BFFP --> PAYV[Bill8:Payments]
    BFFP --> POSTV[Sentin8:Post]
```

## 2. Runtime Architecture

```mermaid
graph TD
    subgraph "ekiosk build"
        BOOT[main.dart runApp] --> SHELL[HkioskApp + KioskShell]
        SHELL --> HOME[KioskHomePage: Check In / Check Out / Collect Key]
        HOME --> SCI[SelfCheckInPage wizard]
        SCI --> BP[BoardingPassPage completion]
        HOME --> SCO[SelfCheckOutPage wizard]
        SCO --> BP2[completion + receipt choice]
        HOME --> WIS[WalkInSearchPage availability]
        WIS --> SCI
        SHELL --> C[BffClient]
        SHELL --> SES[KioskSession state]
    end
    C -->|limited scope /proxy/*| BFF[Sentin8:BFF]
```

- `main.dart` / `app.dart` — entry + `HkioskApp` shell; owns the single
  `BffClient` and the current `KioskSession`.
- `screens/*.dart` — the mode-selection home and four wizard screens; each
  wizard completes or aborts back to home (session reset).
- `models.dart` — session, reservation, add-on, folio, boarding-pass
  contracts.
- `bff_client.dart` — typed kiosk endpoints (incl. `getKioskConfig` and
  `createWalkInBooking` — the terminal-config read and walk-in express
  booking).

### Request lifecycle — self check-in

```mermaid
sequenceDiagram
    autonumber
    actor G as Guest
    participant SCI as SelfCheckInPage
    participant C as BffClient
    participant BFF as Sentin8:BFF
    participant PMS as Hotel8:PMS
    participant PAY as Bill8:Payments
    G->>SCI: identify (name + confirmation / QR)
    SCI->>C: findReservation(query)
    C->>BFF: GET /proxy/pms/rsv/v1/reservations?last_name=&confirmation=
    PMS-->>C: reservation candidates (error → BffException)
    G->>SCI: review summary + select add-ons
    SCI->>C: getAddOns(reservationId)
    C->>BFF: GET /proxy/pms/par/v1/packages?reservation_id=
    PMS-->>C: add-on catalog
    G->>SCI: tap card on terminal
    SCI->>C: authorizeCard/details)
    C->>BFF: POST /proxy/payments/v1/authorizations
    PAY-->>C: authorization (declined → retry branch)
    SCI->>C: checkIn(KioskCheckIn)
    C->>BFF: POST /proxy/pms/fof/v1/checkin
    PMS-->>C: check-in result + room
    SCI-->>G: key encoding step → BoardingPassPage
```

### Request lifecycle — self check-out

```mermaid
sequenceDiagram
    autonumber
    actor G as Guest
    participant SCO as SelfCheckOutPage
    participant C as BffClient
    participant BFF as Sentin8:BFF
    participant PMS as Hotel8:PMS cashiering
    G->>SCO: identify (name + room)
    SCO->>C: getFolioByRoom(roomNumber)
    C->>BFF: GET /proxy/pms/csh/v1/folios?room_number=
    PMS-->>C: KioskFolio (items + outstanding)
    alt outstanding > 0
        G->>SCO: pay on terminal
        SCO->>C: payFolio(...)
        C->>BFF: POST /proxy/payments/v1/payments
        PAY-->>C: capture result
    end
    SCO->>C: checkOut(KioskCheckOut)
    C->>BFF: POST /proxy/pms/csh/v1/checkout
    PMS-->>C: departed + folio settled
    opt email receipt
        SCO->>C: sendReceipt(email)
        C->>BFF: POST /proxy/post/v1/messages
    end
    SCO-->>G: thank-you + key deposit prompt
```

## 3. Data Model

No persistence in the app; sessions are per transaction. Client projections:

```mermaid
erDiagram
    KIOSK_SESSION ||--|| SELF_SERVICE_RESERVATION : "resolves"
    SELF_SERVICE_RESERVATION ||--o{ ADD_ON : "attaches"
    SELF_SERVICE_RESERVATION ||--|| KIOSK_CHECK_IN : "checked in as"
    SELF_SERVICE_RESERVATION ||--|| KIOSK_CHECK_OUT : "checked out as"
    KIOSK_CHECK_OUT ||--|| KIOSK_FOLIO : "settles"
    KIOSK_FOLIO ||--o{ KIOSK_FOLIO_ITEM : "lists"
    KIOSK_SESSION |o--o| BOARDING_PASS : "completes with"
    WALK_IN_SEARCH ||--o{ WALK_IN_ROOM : "finds"
```

State machines rendered by the wizards (authority in PMS/Payments):

```mermaid
stateDiagram-v2
    direction LR
    state "Kiosk session" as SESS {
        [*] --> identifying
        identifying --> reviewing: reservation resolved
        reviewing --> paying: options chosen
        identifying --> aborted: not found / timeout
        reviewing --> aborted: back / timeout
        paying --> completing: payment + domain op ok
        completing --> [*]: session reset
        aborted --> [*]
    }
```

Notes: `KioskMode` selects the wizard; `KioskCheckIn`/`KioskCheckOut` carry
the step outcomes (room, amount, add-on codes) the boarding pass renders.
`KioskFolioItem` types mirror the folio charge categories (room, tax, F&B,
mini bar, other). The mode menu and add-on list come from the property's
`kiosk-config` row (`pms DESIGN.md` §3 "Staff & corporate surfaces") — the
terminal never invents modes; `lockdown=true` freezes the terminal at the
attract loop with a staff-unlock notice (deployment owns the enclosure, the
app owns the freeze).

## 4. API Surface

All kiosk calls traverse the BFF with a limited-scope client. Audience:
self-service kiosk terminal. Paths as implemented in `bff_client.dart`:

| Group | Endpoints (method + proxy path) | Backend |
|---|---|---|
| Identify | `GET /proxy/hotel8-pms/v1/properties/{p}/reservations?last_name=&confirmation=`, `GET .../reservations/{id}` | Hotel8:PMS |
| Walk-in | `POST /proxy/hotel8-pms/v1/properties/{p}/availability` | Hotel8:PMS |
| Walk-in booking | `POST /proxy/hotel8-pms/v1/properties/{p}/walk-in` | express booking: creates a `CONFIRMED` reservation from the selected room type; the wizard then check-ins it (kiosk flow: search → book → check-in → keys) |
| Add-ons | `GET /proxy/hotel8-pms/v1/properties/{p}/packages` | Hotel8:PMS |
| Payment | `POST /proxy/bill8-payments/v1/payment-intents` (+`/{id}/confirm`) as authorization; `POST /proxy/bill8-payments/v1/charges` as capture | Bill8:Payments |
| Check-in | `POST /proxy/hotel8-pms/v1/properties/{p}/reservations/{id}/check-in` + `POST .../digital-keys` | Hotel8:PMS |
| Folio / check-out | `GET /proxy/hotel8-pms/v1/properties/{p}/folios?room_number=`, `POST .../reservations/{id}/check-out` | Hotel8:PMS |
| Receipt email | `POST /proxy/post/v1/send` | Sentin8:Post |
| Boarding pass | `GET /proxy/hotel8-pms/v1/properties/{p}/reservations/{id}/boarding-pass` | Hotel8:PMS |
| Terminal config | `GET /proxy/hotel8-pms/v1/properties/{p}/kiosk-config` | mode menu source of truth (`enabled_modes`, add-ons, `max_keys_per_stay`, `lockdown`) — the bootstrap read gates the journeys; hotel8:PMS kiosk-config row |

### Event flow

The app emits no events. The kiosk journeys produce PMS domain events
(check-in/out, payment, add-on purchase) and hardware-error events surface
through the service-side kiosk event family; the outbox→Bus→trigger chains
belong to Hotel8:PMS (`services/pms/DESIGN.md` §4).

```mermaid
sequenceDiagram
    autonumber
    participant APP as eKiosk
    participant BFF as Sentin8:BFF
    participant FOF as Hotel8:PMS fof
    participant BUS as Sentin8:Bus
    APP->>BFF: POST checkin
    BFF->>FOF: POST /v1/checkin (M2M)
    FOF->>FOF: domain tx + INSERT pms.outbox same tx
    FOF-->>APP: check-in result
    FOF->>BUS: POST /v1/produce (relay)
    note over BUS: e.g. hotel8:pms:reservation:checked_in → housekeeping, upsell consumers
```

## 5. Cross-Cutting Concerns

- **Authentication:** the kiosk holds a limited-scope BFF client (no guest
  session); each wizard step is authorized by that narrow scope set
  downstream.
- **Tenant resolution + RLS:** the BFF resolves env from the kiosk's
  registration/host; guest data is RLS-scoped server-side.
- **Idempotency & exactly-once:** check-in/out and payment capture are
  server-side transactions; double-taps fold onto one domain outcome.
- **Audit:** PMS journals check-in/out, payments and key operations; kiosk
  identity (device) is part of the audit context downstream.
- **Rate limiting / bot protection:** the terminal is on-property; edge rate
  limits still apply to the identification endpoints to resist enumeration —
  the wizard requires multiple identifiers for lookup.
- **TLS posture:** kiosk terminal traffic rides Sentin8:TLS origins.
- **Upgrade drain:** stateless single-terminal build; sessions abort on
  asset reload.

## 6. Failure Modes & Recovery

```mermaid
flowchart TD
    A[wizard step] --> B{call}
    B -->|2xx| C[next step]
    B -->|4xx/5xx| D[BffException — guest-visible message]
    D --> E{recoverable?}
    E -- payment declined --> F[retry card / other method]
    E -- reservation not found --> G[back to identify step]
    B -->|hardware fault| H[abort wizard → session reset → home]
    H --> I[service-side error event + staff monitoring]
```

- **Payment decline mid-check-in:** the wizard returns to the payment step;
  the reservation is untouched until check-in executes.
- **Check-out with unclosable folio:** the wizard stops at the folio step;
  the guest is sent to the desk (server refuses partial check-out).
- **Session timeout:** every wizard returns home with a fresh session; guest
  data never persists between guests.
- **Key encoder failure:** server-confirmed check-in stands; issuance is
  retried at another kiosk or the desk (boarding pass can be printed or
  emailed depending on property config).

## 7. Concurrency & Performance Model

```mermaid
graph LR
    KUI[Kiosk wizard single isolate] --> C[BffClient]
    C --> BFFP[BFF]
    SES[KioskSession mutation] --> KUI
    T[global timeout watcher] --> SES
```

- Single isolate; one active wizard at a time; the session object is the only
  mutable state.
- Identification and availability calls are the hot path; payloads are small
  JSON; refetch per guest (no caching across sessions, by policy).
- One `http.Client` for terminal lifetime.

## 8. Invariants, Insecure-Defaults Rejected, Unsafe Rationale

**Invariants (always true):**

1. The kiosk client never holds a guest identity beyond one wizard session;
   completing or aborting resets it.
2. All money movement is Payments-proxy driven; folio/cashier outcomes are
   PMS-confirmed before the wizard advances.
3. Keys are dispensed only after server-confirmed check-in/identity flow;
   the client cannot force issuance.
4. Every path is `/proxy/*`; non-2xx ⇒ `BffException`.
5. Lookups require multiple identifiers (name + confirmation or name + room)
  — no single-field enumeration.

**Insecure defaults rejected:** guest accounts at the kiosk; persistent
across-guest session state; client-side payment confirmation (render-only);
single-identifier reservation lookup; card data in the app.

**Unsafe code:** none.

## 9. Testing Strategy

```mermaid
graph TD
    UT[Unit: mappers, session step logic] --> WT[Widget: test/widget_test.dart mode screen + wizards mount]
    WT --> E2E[Hotel8 e2e-ts suite15 kiosk flows via BFF\ncheck-in/out and boarding pass]
```

- **Unit** — mappers and session step transitions.
- **Widget** — home modes and wizard mounting.
- **E2E** — the `e2e-ts` kiosk specs drive check-in/out through the browser +
  BFF; hardware steps are out of scope for web E2E; deliberately NOT tested
  here: PMS check-in domain rules, payment capture internals (service-owned).

## 10. Open Questions

- Deployment target for hardware channels (payment terminal, encoder,
  printer) — which platform build ships first, and does the web build remain
  the only target for E2E? (The channel contract mirrors ePOS
  `h8pos_hardware` — `lib/hardware.dart`.)
- Lockdown enclosure ownership (kiosk OS / physical case) — the app-side
  freeze (`lockdown=true` → attract-loop freeze with staff-unlock notice) is
  implemented; the enclosure side is the deployment platform's concern.
- Paid walk-in settlement terms (deposit vs full charge at booking) — the
  walk-in booking + check-in flow is implemented; settlement policy defaults
  to card guarantee and a full folio at check-out.

---

**Design attribution:** hotel8:ekiosk and its underlying concepts were designed by Hamid Jahanzad <Hamid@Jahanzad.com>.
