// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

/// Self Check-In.
///
/// Multi-step kiosk check-in: scan ID → verify reservation → select room →
/// add-ons → payment → print key → digital key. Large touch targets and
/// big fonts for kiosk mode.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../bff_client.dart';
import '../models.dart';

class SelfCheckInPage extends StatefulWidget {
  const SelfCheckInPage({
    super.key,
    required this.client,
    required this.propertyId,
    this.mode = KioskMode.checkIn,
  });

  final BffClient client;

  /// Property the terminal serves (from the App runtime context).
  final String propertyId;

  final KioskMode mode;

  @override
  State<SelfCheckInPage> createState() => _SelfCheckInPageState();
}

class _SelfCheckInPageState extends State<SelfCheckInPage> {
  int _step = 0;
  bool _loading = false;

  final _lastNameController = TextEditingController();
  final _confirmationController = TextEditingController();
  SelfServiceReservation? _reservation;
  List<AddOn> _addOns = const [];
  String? _selectedRoom;
  double _totalDue = 0;
  bool _paymentDone = false;
  bool _keyPrinted = false;

  late final List<String> _steps;

  @override
  void initState() {
    super.initState();
    if (widget.mode == KioskMode.collectKey) {
      _steps = ['Identify', 'Verify', 'Print Key'];
    } else {
      _steps = ['Identify', 'Reservation', 'Room & Add-Ons', 'Payment', 'Key'];
    }
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  bool get _isLast => _step == _steps.length - 1;

  void _next() {
    if (_isLast) return;
    setState(() => _step++);
  }

  void _prev() {
    if (_step == 0) return;
    setState(() => _step--);
  }

  Future<void> _findReservation() async {
    final lastName = _lastNameController.text.trim();
    final confirmation = _confirmationController.text.trim();
    if (lastName.isEmpty || confirmation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter last name and confirmation number.'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final reservation = await widget.client.findReservation(
        propertyId: widget.propertyId,
        lastName: lastName,
        confirmationNumber: confirmation,
      );
      final addOns = await widget.client.getAvailableAddOns(widget.propertyId);
      if (mounted) {
        setState(() {
          _reservation = reservation;
          _addOns = addOns;
          _totalDue = reservation.totalAmount;
          _loading = false;
        });
        _next();
      }
    } on BffException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reservation not found: ${e.message}')),
        );
      }
    }
  }

  void _toggleAddOn(AddOn addOn) {
    setState(() {
      _addOns = _addOns.map((a) {
        if (a.code == addOn.code) {
          final updated = a.copyWith(selected: !a.selected);
          return updated;
        }
        return a;
      }).toList();
      final addOnsTotal = _addOns
          .where((a) => a.selected)
          .fold(0.0, (s, a) => s + a.price * a.nights);
      _totalDue = (_reservation?.totalAmount ?? 0) + addOnsTotal;
    });
  }

  Future<void> _processPayment() async {
    setState(() => _loading = true);
    try {
      // Pre-authorize then capture
      final auth = await widget.client.preAuthorizeCard(
        propertyId: widget.propertyId,
        reservationId: _reservation!.id,
        amount: _totalDue,
      );
      await widget.client.processPayment(
        reservationId: _reservation!.id,
        amount: _totalDue,
      );
      if (mounted) {
        setState(() {
          _paymentDone = true;
          _loading = false;
        });
        _next();
      }
    } on BffException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Payment failed: ${e.message}')));
      }
    }
  }

  Future<void> _checkInAndPrintKey() async {
    setState(() => _loading = true);
    try {
      await widget.client.kioskCheckIn(
        widget.propertyId,
        KioskCheckIn(
          reservationId: _reservation!.id,
          roomNumber: _selectedRoom ?? _reservation!.roomNumber,
          addOns: _addOns,
          amountPaid: _totalDue,
          keyCount: _reservation!.numberOfGuests,
        ),
      );
      if (mounted) {
        setState(() {
          _keyPrinted = true;
          _loading = false;
        });
      }
    } on BffException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-in failed: ${e.message}')),
        );
      }
    }
  }

  void _finish() {
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == KioskMode.collectKey
              ? 'Collect Your Key'
              : 'Self Check-In',
        ),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: List.generate(_steps.length, (i) {
                final isActive = i == _step;
                final isDone = i < _step;
                return Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: isDone
                            ? Colors.green
                            : isActive
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                        child: isDone
                            ? const Icon(
                                Icons.check,
                                size: 20,
                                color: Colors.white,
                              )
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isActive
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : Colors.grey.shade600,
                                ),
                              ),
                      ),
                      if (i < _steps.length - 1)
                        Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color:
                                i < _step ? Colors.green : Colors.grey.shade300,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _buildStep(),
            ),
          ),
          // Navigation
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _prev,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: const Text('Back', style: TextStyle(fontSize: 18)),
                    ),
                  const Spacer(),
                  if (_isLast)
                    FilledButton.icon(
                      onPressed: _loading ? null : _finish,
                      icon: const Icon(Icons.home),
                      label: const Text('Done', style: TextStyle(fontSize: 20)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    )
                  else if (_step == 0)
                    FilledButton.icon(
                      onPressed: _loading ? null : _findReservation,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search),
                      label: Text(
                        _loading ? 'Searching...' : 'Find Reservation',
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    )
                  else if (_step == _steps.length - 2 &&
                      widget.mode != KioskMode.collectKey)
                    FilledButton.icon(
                      onPressed: _loading ? null : _processPayment,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.payment),
                      label: Text(
                        _loading ? 'Processing...' : 'Pay $_totalDueStr',
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    )
                  else if (_step == _steps.length - 1 &&
                      widget.mode != KioskMode.collectKey)
                    FilledButton.icon(
                      onPressed: _loading ? null : _checkInAndPrintKey,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.print),
                      label: Text(
                        _loading ? 'Printing...' : 'Print Key',
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _next,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text(
                        'Continue',
                        style: TextStyle(fontSize: 20),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _totalDueStr =>
      '${_reservation?.currencyCode ?? "USD"} ${_totalDue.toStringAsFixed(2)}';

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepIdentify(
          lastNameController: _lastNameController,
          confirmationController: _confirmationController,
        );
      case 1:
        return _StepReservation(
          reservation: _reservation,
          addOns: _addOns,
          selectedRoom: _selectedRoom,
          onRoomSelected: (room) => setState(() => _selectedRoom = room),
          onToggleAddOn: _toggleAddOn,
          totalDue: _totalDue,
          isCollectKey: widget.mode == KioskMode.collectKey,
        );
      case 2:
        if (widget.mode == KioskMode.collectKey) {
          return _StepPrintKey(
            reservation: _reservation,
            keyPrinted: _keyPrinted,
          );
        }
        return _StepPayment(
          reservation: _reservation,
          totalDue: _totalDue,
          paymentDone: _paymentDone,
        );
      case 3:
        return _StepKey(
          reservation: _reservation,
          roomNumber: _selectedRoom ?? _reservation?.roomNumber,
          keyPrinted: _keyPrinted,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _StepIdentify extends StatelessWidget {
  const _StepIdentify({
    required this.lastNameController,
    required this.confirmationController,
  });
  final TextEditingController lastNameController;
  final TextEditingController confirmationController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Identify Your Reservation',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your last name and confirmation number to retrieve your reservation.',
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: lastNameController,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 24),
          decoration: InputDecoration(
            labelText: 'Last Name',
            labelStyle: const TextStyle(fontSize: 18),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person, size: 32),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: confirmationController,
          style: const TextStyle(fontSize: 24),
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Confirmation Number',
            labelStyle: const TextStyle(fontSize: 18),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.receipt_long, size: 32),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          color: Colors.blue.shade50,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner, size: 32, color: Colors.blue),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'You can also scan the QR code from your pre-arrival email.',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepReservation extends StatelessWidget {
  const _StepReservation({
    required this.reservation,
    required this.addOns,
    required this.selectedRoom,
    required this.onRoomSelected,
    required this.onToggleAddOn,
    required this.totalDue,
    this.isCollectKey = false,
  });

  final SelfServiceReservation? reservation;
  final List<AddOn> addOns;
  final String? selectedRoom;
  final ValueChanged<String> onRoomSelected;
  final ValueChanged<AddOn> onToggleAddOn;
  final double totalDue;
  final bool isCollectKey;

  @override
  Widget build(BuildContext context) {
    if (reservation == null) {
      return const Center(child: Text('No reservation loaded.'));
    }
    final r = reservation!;
    final fmt = DateFormat('MMM d, yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reservation Summary',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BigRow('Guest', r.guestName),
                _BigRow('Confirmation', r.confirmationNumber),
                _BigRow('Check-In', fmt.format(r.arrivalDate)),
                _BigRow('Check-Out', fmt.format(r.departureDate)),
                _BigRow('Nights', r.numberOfNights.toString()),
                _BigRow('Room Type', r.roomTypeName),
                if (r.roomNumber != null) _BigRow('Room', r.roomNumber!),
                _BigRow('Guests', r.numberOfGuests.toString()),
                const Divider(height: 24),
                _BigRow(
                  'Total',
                  '${r.currencyCode} ${r.totalAmount.toStringAsFixed(2)}',
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        if (!isCollectKey && addOns.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Add-Ons',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...addOns.map(
            (addOn) =>
                _AddOnTile(addOn: addOn, onToggle: () => onToggleAddOn(addOn)),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Due',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${r.currencyCode} ${totalDue.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BigRow extends StatelessWidget {
  const _BigRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 22 : 18,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddOnTile extends StatelessWidget {
  const _AddOnTile({required this.addOn, required this.onToggle});
  final AddOn addOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: CheckboxListTile(
        value: addOn.selected,
        onChanged: (_) => onToggle(),
        title: Text(addOn.name, style: const TextStyle(fontSize: 20)),
        subtitle: Text(addOn.description),
        secondary: Text(
          '${addOn.currencyCode} ${addOn.price.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        contentPadding: const EdgeInsets.all(8),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }
}

class _StepPayment extends StatelessWidget {
  const _StepPayment({
    required this.reservation,
    required this.totalDue,
    required this.paymentDone,
  });
  final SelfServiceReservation? reservation;
  final double totalDue;
  final bool paymentDone;

  @override
  Widget build(BuildContext context) {
    if (paymentDone) {
      return _SuccessView(
        icon: Icons.check_circle,
        color: Colors.green,
        title: 'Payment Confirmed',
        message:
            '${reservation?.currencyCode ?? "USD"} ${totalDue.toStringAsFixed(2)} has been charged.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.payment, size: 64, color: Colors.green),
                const SizedBox(height: 16),
                const Text(
                  'Tap, Insert, or Swipe Your Card',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Amount Due: ${reservation?.currencyCode ?? "USD"} ${totalDue.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 24),
                const Text(
                  'The payment terminal is active. Follow the prompts on the terminal to complete your payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepKey extends StatelessWidget {
  const _StepKey({
    required this.reservation,
    required this.roomNumber,
    required this.keyPrinted,
  });
  final SelfServiceReservation? reservation;
  final String? roomNumber;
  final bool keyPrinted;

  @override
  Widget build(BuildContext context) {
    if (keyPrinted) {
      return _SuccessView(
        icon: Icons.check_circle,
        color: Colors.green,
        title: 'Keys Printed!',
        message: 'Please take your key card(s). '
            'Room $roomNumber - Enjoy your stay, ${reservation?.guestName ?? "Guest"}!',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Print Your Room Key',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(Icons.key, size: 72, color: Colors.amber),
                const SizedBox(height: 16),
                const Text(
                  'Place Key Card on the Encoder',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Room $roomNumber',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Place your blank key card on the encoder pad below. '
                  'The key will be encoded automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StepPrintKey extends StatelessWidget {
  const _StepPrintKey({required this.reservation, required this.keyPrinted});
  final SelfServiceReservation? reservation;
  final bool keyPrinted;

  @override
  Widget build(BuildContext context) {
    return _StepKey(
      reservation: reservation,
      roomNumber: reservation?.roomNumber,
      keyPrinted: keyPrinted,
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
