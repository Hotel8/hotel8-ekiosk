// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

/// Boarding Pass.
///
/// Print boarding pass, airline check-in link, flight info. Lets the
/// guest print their boarding pass or link to the airline's online
/// check-in.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../bff_client.dart';
import '../models.dart';

class BoardingPassPage extends StatefulWidget {
  const BoardingPassPage({
    super.key,
    required this.client,
    required this.propertyId,
    required this.reservationId,
  });

  final BffClient client;

  /// Property the terminal serves (from the App runtime context).
  final String propertyId;

  final String reservationId;

  @override
  State<BoardingPassPage> createState() => _BoardingPassPageState();
}

class _BoardingPassPageState extends State<BoardingPassPage> {
  late Future<BoardingPass?> _future;
  bool _printing = false;
  bool _printed = false;
  final _lastNameController = TextEditingController();
  final _confirmationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.reservationId.isNotEmpty) {
      _future =
          widget.client.getBoardingPass(widget.propertyId, widget.reservationId);
    } else {
      _future = Future.value(null);
    }
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final lastName = _lastNameController.text.trim();
    final confirmation = _confirmationController.text.trim();
    if (lastName.isEmpty || confirmation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your last name and confirmation number.')),
      );
      return;
    }
    setState(() {
      _future = widget.client
          .findReservation(
        propertyId: widget.propertyId,
        lastName: lastName,
        confirmationNumber: confirmation,
      )
          .then(
        (res) => widget.client.getBoardingPass(widget.propertyId, res.id),
      );
    });
    await _future;
  }

  Future<void> _printPass() async {
    setState(() => _printing = true);
    // Simulate printing delay
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _printing = false;
        _printed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boarding pass printed! 📄')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boarding Pass'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: widget.reservationId.isEmpty
          ? _LookupForm(
              lastNameController: _lastNameController,
              confirmationController: _confirmationController,
              onLookup: _lookup,
              child: _buildResult(),
            )
          : _buildResult(),
    );
  }

  Widget _buildResult() {
    return FutureBuilder<BoardingPass?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(snap.error is BffException
                    ? (snap.error as BffException).message
                    : '${snap.error}'),
              ],
            ),
          );
        }
        final pass = snap.data;
        if (pass == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flight_takeoff, size: 72,
                      color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('No Flight Information',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text(
                    'No boarding pass information is linked to your reservation.\n'
                    'You can use the airline check-in link below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Go to Airline Check-In'),
                  ),
                ],
              ),
            ),
          );
        }
        return _PassDisplay(
          pass: pass,
          printing: _printing,
          printed: _printed,
          onPrint: _printPass,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _LookupForm extends StatelessWidget {
  const _LookupForm({
    required this.lastNameController,
    required this.confirmationController,
    required this.onLookup,
    required this.child,
  });

  final TextEditingController lastNameController;
  final TextEditingController confirmationController;
  final VoidCallback onLookup;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Find Your Reservation',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: lastNameController,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmationController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: 'Confirmation Number',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onLookup,
                      icon: const Icon(Icons.search),
                      label: const Text('Find Boarding Pass'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PassDisplay extends StatelessWidget {
  const _PassDisplay({
    required this.pass,
    required this.printing,
    required this.printed,
    required this.onPrint,
  });

  final BoardingPass pass;
  final bool printing;
  final bool printed;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('EEE, MMM d • h:mm a');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Boarding pass card
          Card(
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: theme.colorScheme.primary,
                  child: Row(
                    children: [
                      Icon(Icons.flight, color: theme.colorScheme.onPrimary, size: 32),
                      const SizedBox(width: 12),
                      Text(pass.airline,
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary)),
                      const Spacer(),
                      Text('Flight ${pass.flightNumber}',
                          style: TextStyle(fontSize: 20, color: theme.colorScheme.onPrimary)),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Route
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _AirportCode(code: pass.departureAirport),
                          Icon(Icons.flight_takeoff,
                              color: theme.colorScheme.primary, size: 40),
                          _AirportCode(code: pass.arrivalAirport),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoRow('Passenger', pass.passengerName),
                      _InfoRow('Departure', fmt.format(pass.departureTime)),
                      if (pass.gate != null) _InfoRow('Gate', pass.gate!),
                      if (pass.seat != null) _InfoRow('Seat', pass.seat!),
                      if (pass.boardingGroup != null)
                        _InfoRow('Boarding Group', pass.boardingGroup!),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Actions
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: printing ? null : onPrint,
              icon: printing
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : (printed ? const Icon(Icons.check) : const Icon(Icons.print)),
              label: Text(
                printing ? 'Printing...' : printed ? 'Printed!' : 'Print Boarding Pass',
                style: const TextStyle(fontSize: 20),
              ),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          ),
          const SizedBox(height: 12),
          if (pass.checkInUrl != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Opening: ${pass.checkInUrl}')),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Airline Online Check-In',
                    style: TextStyle(fontSize: 20)),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
            ),
          const SizedBox(height: 24),
          // Info
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Boarding pass printing is available 24 hours before '
                      'departure. Online check-in is available on the airline website.',
                      style: TextStyle(fontSize: 16),
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
}

class _AirportCode extends StatelessWidget {
  const _AirportCode({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(code,
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
        Text(_airportName(code), style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      ],
    );
  }

  String _airportName(String code) {
    const names = {
      'JFK': 'New York',
      'LAX': 'Los Angeles',
      'LHR': 'London Heathrow',
      'CDG': 'Paris',
      'DXB': 'Dubai',
      'HND': 'Tokyo Haneda',
      'SIN': 'Singapore',
      'FRA': 'Frankfurt',
      'AMS': 'Amsterdam',
    };
    return names[code] ?? '';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}