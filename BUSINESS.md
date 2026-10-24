# Hotel8:eKiosk - Business Requirements & Functionality

> Audience: product owners, business analysts, and anyone evaluating what
> Hotel8:eKiosk **does for the business**. For architecture read `README.md`;
> for wire-level detail read `DESIGN.md`.

## 1. Business Purpose

- Remove routine check-in/out transactions from the front desk by absorbing
  them into self-service lobby terminals - reduce queue length and free
  staff for exceptions.
- Monetize the check-in moment with add-on offers (breakfast, late
  check-out, parking, spa, upgrades) chosen interactively before payment.
- Guarantee key dispensing in under a minute for guests who checked in
  online, completing the eGuest mobile journey.
- Keep 24/7 lobby service available with property branding and no staff
  intervention.

## 2. Business Scope (What the Service Provides)

| Capability | Provided by eKiosk |
|---|---|
| Mode selection (Check In / Check Out / Collect Key) | ✅ |
| Self check-in wizard: identify → summary → add-ons → pay → keys | ✅ |
| Self check-out wizard: identify → folio → pay → receipt | ✅ |
| Walk-in search + booking from availability | ✅ select a room → express booking (CONFIRMED walk-in reservation) → self check-in wizard |
| Boarding-pass/key-collection flow | ✅ |
| Email receipt | ✅ (Post proxy) |
| Payment terminal integration (chip & PIN, NFC) | ✅ flows built; hardware rides the terminal channel contract - deployment build pending |
| Key encoder integration (Assa Abloy / Dormakaba) | ✅ flows built; vendor handoff via the hardware channel - deployment build pending |
| Email receipts | ✅ (Sentin8:Post) - thermal printing rides the hardware channel on embedding builds |
| Kiosk lockdown freeze | ✅ `lockdown=true` (property kiosk-config) freezes the terminal at the attract loop with a staff-unlock notice; enclosure/OS hardening stays a deployment concern |
| `/admin` kiosk configuration | ❌ service-side admin surface |
| Mobile guest experience | ❌ delegated - Hotel8:eGuest |
| Complex/group check-ins | ❌ delegated - front desk (Hotel8:ePMS) |

## 3. Business Capabilities

### Self check-in

| Capability | Business rule |
|---|---|
| Identification | A reservation is resolved only with multiple identifiers (name + confirmation number, or name + arrival date, or QR); single-field lookups are refused. |
| Summary review | Guest verifies dates, room type, rate, total due, and applies extra guest names before paying. |
| Add-on purchase | Add-ons come from the PMS catalog; each has a price that joins the running total before payment - nothing is added silently. |
| Payment | Payment is pre-authorized/captured through the Payments proxy on the terminal; the kiosk never handles card data. |
| Key encoding | Keys are encoded only after server-confirmed check-in; the number of keys follows the reservation's guest count. |

### Self check-out

| Capability | Business rule |
|---|---|
| Folio review | The guest sees the authoritative folio breakdown and outstanding balance. |
| Settlement | An outstanding balance is paid on the terminal; check-out executes only when the folio is settled server-side. |
| Receipt | The guest chooses printed (hardware) or emailed receipt; the stay departs in PMS and housekeeping is triggered downstream. |

### Key collection ("Collect Your Key")

| Capability | Business rule |
|---|---|
| Key pickup | Guests who checked in online (eGuest) identify with name + confirmation (or QR) and collect keys in under 60 seconds, verified against the PMS reservation. |
| Walk-in | Availability search shows bookable rooms; express booking creates the walk-in reservation (source `WALKIN`) and the wizard completes check-in - the terminal stays availability-gated and never oversells. |
| Terminal config | The property's kiosk-config row governs the terminal: enabled modes, add-on catalog codes, max keys per stay, and the lockdown flag - the terminal never offers more than the hotel configured. |

## 4. Business Events (Outbound)

eKiosk emits no events of its own; the journeys create events in Hotel8:PMS
(check-in/out, payment, add-on purchase) and staff-side error/monitoring
events. See `services/pms/DESIGN.md` §4.

| Business moment | Event family (owner) |
|---|---|
| Self check-in completed | PMS reservation/check-in events |
| Add-on purchased | PMS package/payment events |
| Self check-out completed | PMS cashiering events |
| Key issued | PMS key events |
| Kiosk hardware fault | Service-side kiosk monitoring events |

**Inbound:** none.

## 5. Business Rules & Invariants

1. A kiosk session serves exactly one guest transaction; it resets on
   completion, abort, or timeout - no data survives between guests.
2. Payment success and check-in/check-out are server-confirmed outcomes; the
   kiosk never confirms them locally.
3. Keys are issued only after a server-confirmed check-in/identity flow.
4. Card data exists only inside the payment terminal + Payments proxy path;
   the kiosk app never receives it.
5. The check-out wizard cannot advance past an unsettled folio.
6. Identification requires multiple fields, resistant to enumeration.
7. All traffic is BFF-proxied with a limited-scope kiosk client.

## 6. Target-User Roles & Use Cases

| Persona | What they do with eKiosk |
|---|---|
| Arriving guest | Self check-in with add-ons, pays and collects keys without queueing. |
| Departing guest | Reviews folio, settles, takes receipt, deposits keys. |
| Online-arrived guest (eGuest user) | Collects keys in under a minute via QR. |
| Front-desk staff | Handles only exceptions; benefits from reduced queue load. |
| Property manager | Configures kiosk modes/branding/add-on catalog (via service-side admin). |

## 7. KPIs / Success Criteria

- **Self-service share** - percentage of check-ins/outings completed at the
  kiosk vs desk.
- **Key collection time** - under 60 seconds for the Collect-Your-Key flow.
- **Add-on attach rate** and add-on revenue per check-in.
- **Exception rate** - wizard aborts per day trending down; hardware error
  events resolved within staff SLA.
- **Payment integrity** - terminal captures match PMS folio postings with
  zero manual correction.

## 8. Dependencies & Reliance on Other Services

| Reliance | For |
|---|---|
| Hotel8:PMS | Reservation lookup, check-in/out, folio, keys, boarding pass |
| Bill8:Payments | Card authorization + capture (via BFF) |
| Sentin8:Post | Email receipts |
| Sentin8:BFF | Transport, limited-scope kiosk client, tenant resolution |
| Hotel8:eGuest | Online check-in + QR for the Collect-Your-Key flow |
| Vendor hardware | Terminal, key encoder, printer (via platform channels) |
| Sentin8:App | Listing, runtime context, DCR bootstrap |

## 9. Acceptance Criteria

1. A guest completes self check-in - identify, review, choose add-ons, pay,
   collect key - in a single unstaffed session.
2. A guest self-checks out with a settled folio and receives a receipt.
3. An outstanding-balance check-out cannot pass the folio step until paid.
4. A pre-checked-in guest collects keys in under 60 seconds using their QR
   code.
5. A wizard abort or timeout leaves no guest data on the terminal.
6. Every money movement reflects Payments-capture and PMS-folio confirmations
   - no local-only confirmations at any step.

## 10. Open Business Questions

- Which hardware vendors/encoders are the first deployment targets, and does
  the kiosk ship on the platform-channel build only?
- Should walk-in stays complete on the kiosk (with deposits) once walk-in
  business rules are finalized in PMS?
- Where does the kiosk `/admin` surface live (service RFW vs app), and what
  is staff's real-time monitoring view?
- Payment-terminals: direct-to-terminal or terminal-as-a-service, and who
  owns the PCI scope boundary?

---

**Architecture & Design:** hotel8:ekiosk and its underlying concepts were designed by [Hamid Jahanzad](https://www.linkedin.com/in/hamidjahanzad/).
