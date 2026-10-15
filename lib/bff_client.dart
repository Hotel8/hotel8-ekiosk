// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

/// Hkiosk BFF client.
///
/// Thin HTTP client that calls the BFF proxy endpoints (see
/// `ekiosk/DESIGN.md` §4) which in turn
/// delegate to PMS / Payments / Upsell / Post. All requests go through the
/// BFF server-side token guardian. The kiosk uses a limited-scope
/// OAuth client — no guest login.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'models.dart';

class BffClient {
  BffClient({String? baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl ?? _resolveBaseUrl(),
        _httpClient = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _httpClient;
  String? _authToken;

  /// Resolve the BFF base URL. In production this is the kiosk-scoped
  /// BFF domain (e.g. `https://bff.kiosk.demo-hotel.pms.sentin8.dev`).
  /// For local development fall back to the `HKIOSK_BFF_BASE_URL` env
  /// var or `http://localhost:8080`.
  static String _resolveBaseUrl() {
    const env = String.fromEnvironment('HKIOSK_BFF_BASE_URL', defaultValue: '');
    if (env.isNotEmpty) return env;

    if (kIsWeb) return '';
    return 'http://localhost:8080';
  }

  String _path(String p) => '$_baseUrl$p';

  void setAuthToken(String? token) => _authToken = token;

  Future<Map<String, dynamic>> _getJson(String path) async {
    final resp = await _httpClient.get(
      Uri.parse(_path(path)),
      headers: _headers(),
    );
    return _handle(resp);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _httpClient.post(
      Uri.parse(_path(path)),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _handle(resp);
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  Future<Map<String, dynamic>> _handle(http.Response resp) async {
    final body = resp.body.isEmpty ? '{}' : resp.body;
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(body) as Map<String, dynamic>;
    }
    String message;
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      message =
          decoded['message'] as String? ?? decoded['error'] as String? ?? body;
    } catch (_) {
      message = body;
    }
    throw BffException(resp.statusCode, message);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Reservation lookup
  // ═════════════════════════════════════════════════════════════════════════

  /// `GET /proxy/hotel8-pms/v1/properties/{propertyId}/reservations?last_name=&confirmation=`
  ///
  /// Kiosk identification: last name + confirmation number (multi-field,
  /// per `ekiosk/DESIGN.md` §8 — no single-identifier enumeration).
  Future<SelfServiceReservation> findReservation({
    required String propertyId,
    required String lastName,
    String? confirmationNumber,
  }) async {
    final qs = <String>['last_name=${Uri.encodeComponent(lastName)}'];
    if (confirmationNumber != null && confirmationNumber.isNotEmpty) {
      qs.add('confirmation=${Uri.encodeComponent(confirmationNumber)}');
    }
    final json = await _getJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/reservations?${qs.join('&')}',
    );
    final items = (json['items'] as List<dynamic>?) ?? const [];
    if (items.isEmpty) {
      throw const BffException(404, 'No reservation matches those details');
    }
    return SelfServiceReservation.fromJson(items.first as Map<String, dynamic>);
  }

  /// `GET /proxy/hotel8-pms/v1/properties/{propertyId}/reservations/{id}`
  Future<SelfServiceReservation> getReservationDetail(
    String propertyId,
    String id,
  ) async {
    final json = await _getJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/reservations/$id',
    );
    return SelfServiceReservation.fromJson(json);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Walk-in search
  // ═════════════════════════════════════════════════════════════════════════

  /// `POST /proxy/hotel8-pms/v1/properties/{propertyId}/availability`
  ///
  /// Walk-in search rides the PMS availability engine (rate plans from
  /// the response feed the booking step at the desk; the kiosk search
  /// surfaces bookable room types).
  Future<List<WalkInRoom>> searchWalkInAvailability(
    String propertyId,
    WalkInSearch search,
  ) async {
    final json = await _postJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/availability',
      search.toJson(),
    );
    final list = json['room_types'] as List<dynamic>? ??
        json['rooms'] as List<dynamic>? ??
        json['items'] as List<dynamic>? ??
        const [];
    return list
        .map((e) => WalkInRoom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Add-ons / Upsell
  // ═════════════════════════════════════════════════════════════════════════

  /// `GET /proxy/hotel8-pms/v1/properties/{propertyId}/packages`
  Future<List<AddOn>> getAvailableAddOns(String propertyId) async {
    final json = await _getJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/packages',
    );
    final list = json['items'] as List<dynamic>? ??
        json['packages'] as List<dynamic>? ??
        const [];
    return list.map((e) => AddOn.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Payment
  // ═════════════════════════════════════════════════════════════════════════

  /// `POST /proxy/bill8-payments/v1/payment-intents` + `/{id}/confirm`
  ///
  /// Terminal pre-authorization maps to a bill8 payment intent with
  /// manual confirm (pms DESIGN.md §4 Authorization mapping): create the
  /// intent, confirm it, return both payloads.
  Future<Map<String, dynamic>> preAuthorizeCard({
    required String propertyId,
    required String reservationId,
    required double amount,
    String currencyCode = 'USD',
  }) async {
    final intent = await _postJson('/proxy/bill8-payments/v1/payment-intents', {
      'amount': amount.toStringAsFixed(2),
      'currency': currencyCode,
      'idempotency_key':
          'hotel8-ekiosk:$propertyId:$reservationId:$_dateStr(DateTime.now())',
    });
    final intentId = intent['id'] as String;
    final confirmed = await _postJson(
      '/proxy/bill8-payments/v1/payment-intents/$intentId/confirm',
      {},
    );
    return {'intent': intent, 'confirmation': confirmed};
  }

  /// `POST /proxy/bill8-payments/v1/charges` — capture.
  Future<Map<String, dynamic>> processPayment({
    required String reservationId,
    required double amount,
    String currencyCode = 'USD',
    String? paymentMethodId,
  }) async {
    return _postJson('/proxy/bill8-payments/v1/charges', {
      'amount': amount.toStringAsFixed(2),
      'currency': currencyCode,
      if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
      'idempotency_key':
          'hotel8-ekiosk:$reservationId:${DateTime.now().millisecondsSinceEpoch}',
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Check-in / Check-out
  // ═════════════════════════════════════════════════════════════════════════

  /// `POST /proxy/hotel8-pms/v1/properties/{propertyId}/reservations/{id}/check-in`
  /// then `POST .../digital-keys` for the key count.
  Future<Map<String, dynamic>> kioskCheckIn(
    String propertyId,
    KioskCheckIn request,
  ) async {
    final result = await _postJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/reservations/${request.reservationId}/check-in',
      {if (request.roomNumber != null) 'room_number': request.roomNumber},
    );
    await _postJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/digital-keys',
      {'reservation_id': request.reservationId, 'count': request.keyCount},
    );
    return result;
  }

  /// `GET /proxy/hotel8-pms/v1/properties/{propertyId}/folios?room_number=`
  ///
  /// Settlement view for the in-house stay in a room (kiosk check-out step).
  Future<KioskFolio> getFolioByRoom(
    String propertyId,
    String roomNumber,
  ) async {
    final json = await _getJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/folios?room_number=${Uri.encodeComponent(roomNumber)}',
    );
    return KioskFolio.fromJson(json);
  }

  /// `POST /proxy/hotel8-pms/v1/properties/{propertyId}/reservations/{id}/check-out`
  /// (the stay is resolved by room + name before this step).
  Future<Map<String, dynamic>> kioskCheckOut(
    String propertyId,
    String reservationId,
    KioskCheckOut request,
  ) async {
    return _postJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/reservations/$reservationId/check-out',
      {
        'payment_method':
            request.paymentMethodToken != null ? 'CREDIT_CARD' : 'CASH',
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Boarding pass / Receipt
  // ═════════════════════════════════════════════════════════════════════════

  /// `POST /proxy/post/v1/send` — email receipt via Sentin8:Post.
  Future<void> emailReceipt({
    required String to,
    required String folioId,
  }) async {
    await _postJson('/proxy/post/v1/send', {
      'message_type': 'EMAIL',
      'category': 'RECEIPT',
      'recipient_email': to,
      'subject': 'Your receipt',
      'body': 'Thank you for staying with us. Folio $folioId is settled.',
      'body_format': 'text',
      'metadata': {'folio_id': folioId},
    });
  }

  /// `GET /proxy/hotel8-pms/v1/properties/{propertyId}/reservations/{id}/boarding-pass`
  ///
  /// The check-in completion artifact (room, dates, guest, key count).
  // ═════════════════════════════════════════════════════════════════════
  // Terminal config (pms kiosk-config row — mode menu source of truth)
  // ═════════════════════════════════════════════════════════════════════

  /// `GET .../kiosk-config` — the property's terminal configuration
  /// (`enabled_modes`, `addon_package_codes`, `max_keys_per_stay`, `lockdown`).
  Future<KioskConfig> getKioskConfig(String propertyId) async {
    final json = await _getJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/kiosk-config',
    );
    return KioskConfig.fromJson(json);
  }

  // ═════════════════════════════════════════════════════════════════════
  // Walk-in express booking (pms walk-in surface)
  // ═════════════════════════════════════════════════════════════════════

  /// `POST .../walk-in` — create a `CONFIRMED` reservation from the selected
  /// room type; the wizard then check-ins it via the normal kioskCheckIn.
  Future<SelfServiceReservation> createWalkInBooking({
    required String propertyId,
    required String roomTypeId,
    required DateTime arrivalDate,
    required DateTime departureDate,
    String firstName = '',
    String lastName = 'Walk-in',
    int numRooms = 1,
  }) async {
    String _d(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final json = await _postJson(
      '/proxy/hotel8-pms/v1/properties/$propertyId/walk-in',
      {
        'room_type_id': roomTypeId,
        'arrival_date': _d(arrivalDate),
        'departure_date': _d(departureDate),
        'first_name': firstName,
        'last_name': lastName,
        'num_rooms': numRooms,
      },
    );
    return SelfServiceReservation.fromJson(json);
  }

  Future<BoardingPass?> getBoardingPass(
    String propertyId,
    String reservationId,
  ) async {
    try {
      final json = await _getJson(
        '/proxy/hotel8-pms/v1/properties/$propertyId/reservations/$reservationId/boarding-pass',
      );
      return BoardingPass.fromJson(json);
    } on BffException {
      return null;
    }
  }

  void close() => _httpClient.close();
}

class BffException implements Exception {
  final int statusCode;
  final String message;
  const BffException(this.statusCode, this.message);

  @override
  String toString() => 'BffException($statusCode): $message';
}

String _dateStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
