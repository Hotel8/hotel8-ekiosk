// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

/// Hkiosk data models.
///
/// Simple Dart classes mirroring the PMS / Payments / Upsell contract shapes
/// (see `ekiosk/DESIGN.md` §3–4) and the
/// BFF proxy surface for Hkiosk. Hkiosk is the self-service lobby kiosk
/// counterpart to the Guest App's mobile check-in/out.

// ═══════════════════════════════════════════════════════════════════════════
// Kiosk Session
// ═══════════════════════════════════════════════════════════════════════════

enum KioskMode {
  checkIn,
  checkOut,
  collectKey,
  walkIn;

  static KioskMode fromString(String s) => KioskMode.values.firstWhere(
        (e) => e.name.toLowerCase() == s.toLowerCase().replaceAll('_', ''),
        orElse: () => KioskMode.checkIn,
      );

  String get label => switch (this) {
        KioskMode.checkIn => 'Check In',
        KioskMode.checkOut => 'Check Out',
        KioskMode.collectKey => 'Collect Your Key',
        KioskMode.walkIn => 'Walk-In',
      };
}

class KioskSession {
  final String id;
  final String kioskId;
  final KioskMode mode;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? reservationId;
  final String? guestName;

  const KioskSession({
    required this.id,
    required this.kioskId,
    required this.mode,
    required this.startedAt,
    this.endedAt,
    this.reservationId,
    this.guestName,
  });

  factory KioskSession.fromJson(Map<String, dynamic> json) => KioskSession(
        id: json['id'] as String,
        kioskId: json['kiosk_id'] as String? ?? '',
        mode: KioskMode.fromString(json['mode'] as String? ?? 'check_in'),
        startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ??
            DateTime.now(),
        endedAt: json['ended_at'] != null
            ? DateTime.tryParse(json['ended_at'] as String)
            : null,
        reservationId: json['reservation_id'] as String?,
        guestName: json['guest_name'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Self-Service Reservation (retrieved at kiosk)
// ═══════════════════════════════════════════════════════════════════════════

class SelfServiceReservation {
  final String id;
  final String confirmationNumber;
  final String guestName;
  final String? guestEmail;
  final String? guestPhone;
  final DateTime arrivalDate;
  final DateTime departureDate;
  final int numberOfNights;
  final int numberOfGuests;
  final int numberOfRooms;
  final String roomTypeCode;
  final String roomTypeName;
  final String? roomNumber;
  final String ratePlanName;
  final double rateAmount;
  final double totalAmount;
  final String currencyCode;
  final List<AddOn> addOns;
  final String? status;
  final bool checkedIn;

  const SelfServiceReservation({
    required this.id,
    required this.confirmationNumber,
    required this.guestName,
    this.guestEmail,
    this.guestPhone,
    required this.arrivalDate,
    required this.departureDate,
    this.numberOfNights = 1,
    this.numberOfGuests = 1,
    this.numberOfRooms = 1,
    required this.roomTypeCode,
    required this.roomTypeName,
    this.roomNumber,
    this.ratePlanName = '',
    this.rateAmount = 0.0,
    this.totalAmount = 0.0,
    this.currencyCode = 'USD',
    this.addOns = const [],
    this.status,
    this.checkedIn = false,
  });

  factory SelfServiceReservation.fromJson(Map<String, dynamic> json) =>
      SelfServiceReservation(
        id: json['id'] as String,
        confirmationNumber: json['confirmation_number'] as String? ?? '',
        guestName: json['guest_name'] as String? ?? '',
        guestEmail: json['guest_email'] as String?,
        guestPhone: json['guest_phone'] as String?,
        arrivalDate: DateTime.tryParse(json['arrival_date'] as String? ?? '') ??
            DateTime.now(),
        departureDate:
            DateTime.tryParse(json['departure_date'] as String? ?? '') ??
                DateTime.now(),
        numberOfNights: (json['number_of_nights'] as num?)?.toInt() ?? 1,
        numberOfGuests: (json['number_of_guests'] as num?)?.toInt() ?? 1,
        numberOfRooms: (json['number_of_rooms'] as num?)?.toInt() ?? 1,
        roomTypeCode: json['room_type_code'] as String? ?? '',
        roomTypeName: json['room_type_name'] as String? ?? '',
        roomNumber: json['room_number'] as String?,
        ratePlanName: json['rate_plan_name'] as String? ?? '',
        rateAmount: (json['rate_amount'] as num?)?.toDouble() ?? 0.0,
        totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
        currencyCode: json['currency_code'] as String? ?? 'USD',
        addOns: (json['add_ons'] as List<dynamic>?)
                ?.map((e) => AddOn.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        status: json['status'] as String?,
        checkedIn: json['checked_in'] as bool? ?? false,
      );

  double get addOnsTotal => addOns
      .where((a) => a.selected)
      .fold(0.0, (sum, a) => sum + a.price * a.nights);
  double get grandTotal => totalAmount + addOnsTotal;
}

// ═══════════════════════════════════════════════════════════════════════════
// Add-On (upsell at kiosk)
// ═══════════════════════════════════════════════════════════════════════════

class AddOn {
  final String code;
  final String name;
  final String description;
  final double price;
  final int nights;
  final String currencyCode;
  final bool selected;

  const AddOn({
    required this.code,
    required this.name,
    required this.description,
    required this.price,
    this.nights = 1,
    this.currencyCode = 'USD',
    this.selected = false,
  });

  factory AddOn.fromJson(Map<String, dynamic> json) => AddOn(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        nights: (json['nights'] as num?)?.toInt() ?? 1,
        currencyCode: json['currency_code'] as String? ?? 'USD',
        selected: json['selected'] as bool? ?? false,
      );

  AddOn copyWith({bool? selected, int? nights}) => AddOn(
        code: code,
        name: name,
        description: description,
        price: price,
        nights: nights ?? this.nights,
        currencyCode: currencyCode,
        selected: selected ?? this.selected,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Walk-In Search
// ═══════════════════════════════════════════════════════════════════════════

class WalkInSearch {
  final DateTime arrivalDate;
  final DateTime departureDate;
  final int numberOfGuests;
  final int numberOfRooms;

  const WalkInSearch({
    required this.arrivalDate,
    required this.departureDate,
    this.numberOfGuests = 1,
    this.numberOfRooms = 1,
  });

  Map<String, dynamic> toJson() => {
        'arrival_date': _dateStr(arrivalDate),
        'departure_date': _dateStr(departureDate),
        'number_of_guests': numberOfGuests,
        'number_of_rooms': numberOfRooms,
      };
}

class WalkInRoom {
  final String roomNumber;
  final String floorNumber;
  final String roomTypeId;
  final String roomTypeCode;
  final String roomTypeName;
  final double ratePerNight;
  final String currencyCode;
  final bool available;
  final List<String> features;

  const WalkInRoom({
    required this.roomNumber,
    required this.floorNumber,
    this.roomTypeId = '',
    required this.roomTypeCode,
    required this.roomTypeName,
    required this.ratePerNight,
    this.currencyCode = 'USD',
    this.available = true,
    this.features = const [],
  });

  factory WalkInRoom.fromJson(Map<String, dynamic> json) => WalkInRoom(
        roomNumber: json['room_number'] as String? ?? '',
        floorNumber: json['floor_number'] as String? ?? '',
        roomTypeId: json['room_type_id'] as String? ?? '',
        roomTypeCode: json['room_type_code'] as String? ?? '',
        roomTypeName: json['room_type_name'] as String? ?? '',
        ratePerNight: (json['rate_per_night'] as num?)?.toDouble() ?? 0.0,
        currencyCode: json['currency_code'] as String? ?? 'USD',
        available: json['available'] as bool? ?? true,
        features:
            (json['features'] as List<dynamic>?)?.cast<String>() ?? const [],
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Kiosk Check-In / Check-Out
// ═══════════════════════════════════════════════════════════════════════════

class KioskCheckIn {
  final String reservationId;
  final String? roomNumber;
  final List<AddOn> addOns;
  final String? paymentMethodToken;
  final double? amountPaid;
  final int keyCount;

  const KioskCheckIn({
    required this.reservationId,
    this.roomNumber,
    this.addOns = const [],
    this.paymentMethodToken,
    this.amountPaid,
    this.keyCount = 1,
  });

  Map<String, dynamic> toJson() => {
        'reservation_id': reservationId,
        'room_number': roomNumber,
        'add_ons': addOns.where((a) => a.selected).map((a) => a.code).toList(),
        'payment_method_token': paymentMethodToken,
        'amount_paid': amountPaid,
        'key_count': keyCount,
      };
}

class KioskCheckOut {
  final String roomNumber;
  final String? lastName;
  final String? paymentMethodToken;
  final bool printReceipt;
  final bool emailReceipt;
  final String? email;

  const KioskCheckOut({
    required this.roomNumber,
    this.lastName,
    this.paymentMethodToken,
    this.printReceipt = true,
    this.emailReceipt = false,
    this.email,
  });

  Map<String, dynamic> toJson() => {
        'room_number': roomNumber,
        'last_name': lastName,
        'payment_method_token': paymentMethodToken,
        'print_receipt': printReceipt,
        'email_receipt': emailReceipt,
        'email': email,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// Folio (checkout charges)
// ═══════════════════════════════════════════════════════════════════════════

class KioskFolioItem {
  final String id;
  final DateTime date;
  final String description;
  final double amount;
  final String currencyCode;
  final String category;

  const KioskFolioItem({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.currencyCode = 'USD',
    this.category = 'other',
  });

  factory KioskFolioItem.fromJson(Map<String, dynamic> json) => KioskFolioItem(
        id: json['id'] as String,
        date:
            DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        currencyCode: json['currency_code'] as String? ?? 'USD',
        category: json['category'] as String? ?? 'other',
      );
}

class KioskFolio {
  final String id;
  final String reservationId;
  final String guestName;
  final String roomNumber;
  final List<KioskFolioItem> charges;
  final List<KioskFolioItem> payments;
  final double balance;
  final String currencyCode;

  const KioskFolio({
    required this.id,
    required this.reservationId,
    required this.guestName,
    required this.roomNumber,
    this.charges = const [],
    this.payments = const [],
    this.balance = 0.0,
    this.currencyCode = 'USD',
  });

  factory KioskFolio.fromJson(Map<String, dynamic> json) => KioskFolio(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String? ?? '',
        guestName: json['guest_name'] as String? ?? '',
        roomNumber: json['room_number'] as String? ?? '',
        charges: (json['charges'] as List<dynamic>?)
                ?.map((e) => KioskFolioItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        payments: (json['payments'] as List<dynamic>?)
                ?.map((e) => KioskFolioItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
        currencyCode: json['currency_code'] as String? ?? 'USD',
      );

  double get totalCharges =>
      charges.fold(0.0, (sum, item) => sum + item.amount);
}

// ═══════════════════════════════════════════════════════════════════════════
// Boarding Pass
// ═══════════════════════════════════════════════════════════════════════════

class BoardingPass {
  final String passengerName;
  final String airline;
  final String flightNumber;
  final String departureAirport;
  final String arrivalAirport;
  final DateTime departureTime;
  final String? gate;
  final String? seat;
  final String? boardingGroup;
  final String? checkInUrl;

  const BoardingPass({
    required this.passengerName,
    required this.airline,
    required this.flightNumber,
    required this.departureAirport,
    required this.arrivalAirport,
    required this.departureTime,
    this.gate,
    this.seat,
    this.boardingGroup,
    this.checkInUrl,
  });

  factory BoardingPass.fromJson(Map<String, dynamic> json) => BoardingPass(
        passengerName: json['passenger_name'] as String? ?? '',
        airline: json['airline'] as String? ?? '',
        flightNumber: json['flight_number'] as String? ?? '',
        departureAirport: json['departure_airport'] as String? ?? '',
        arrivalAirport: json['arrival_airport'] as String? ?? '',
        departureTime:
            DateTime.tryParse(json['departure_time'] as String? ?? '') ??
                DateTime.now(),
        gate: json['gate'] as String?,
        seat: json['seat'] as String?,
        boardingGroup: json['boarding_group'] as String?,
        checkInUrl: json['check_in_url'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════════════════════

String _dateStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The property's kiosk terminal configuration (pms `kiosk-config` row) —
/// the mode-menu source of truth (ekiosk/DESIGN.md §3). `lockdown=true`
/// freezes the terminal at the attract loop.
class KioskConfig {
  final List<String> enabledModes;
  final List<String> addonPackageCodes;
  final int maxKeysPerStay;
  final bool lockdown;

  const KioskConfig({
    this.enabledModes = const ['CHECK_IN', 'CHECK_OUT', 'COLLECT_KEY'],
    this.addonPackageCodes = const [],
    this.maxKeysPerStay = 4,
    this.lockdown = false,
  });

  factory KioskConfig.fromJson(Map<String, dynamic> json) => KioskConfig(
        enabledModes: ((json['enabled_modes'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        addonPackageCodes:
            ((json['addon_package_codes'] as List<dynamic>?) ?? const [])
                .map((e) => e as String)
                .toList(),
        maxKeysPerStay: (json['max_keys_per_stay'] as num?)?.toInt() ?? 4,
        lockdown: json['lockdown'] as bool? ?? false,
      );

  bool allows(String mode) => enabledModes.contains(mode);
}
