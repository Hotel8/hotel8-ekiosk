// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

/// Self Check-Out.
///
/// Scan key / enter room number → review folio → pay → print or email
/// receipt → digital signature. Large touch targets for kiosk mode.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../bff_client.dart';
import '../models.dart';

class SelfCheckOutPage extends StatefulWidget {
  const SelfCheckOutPage({
    super.key,
    required this.client,
    required this.propertyId,
  });

  final BffClient client;

  /// Property the terminal serves (from the App runtime context).
  final String propertyId;

  @override
  State<SelfCheckOutPage> createState() => _SelfCheckOutPageState();
}

class _SelfCheckOutPageState extends State<SelfCheckOutPage> {
  int _step = 0;
  bool _loading = false;

  final _roomNumberController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  KioskFolio? _folio;
  bool _printReceipt = true;
  bool _emailReceipt = false;
  bool _paymentDone = false;
  bool _checkedOut = false;

  final _steps = ['Identify', 'Folio', 'Payment', 'Receipt'];

  @override
  void dispose() {
    _roomNumberController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
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

  Future<void> _findFolio() async {
    final roomNumber = _roomNumberController.text.trim();
    if (roomNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your room number.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final folio = await widget.client.getFolioByRoom(
        widget.propertyId,
        roomNumber,
      );
      if (mounted) {
        setState(() {
          _folio = folio;
          _loading = false;
        });
        _next();
      }
    } on BffException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Folio not found: ${e.message}')),
        );
      }
    }
  }

  Future<void> _processPayment() async {
    if (_folio == null || _folio!.balance <= 0) {
      // No payment needed - proceed directly
      _next();
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = await widget.client.preAuthorizeCard(
        propertyId: widget.propertyId,
        reservationId: _folio!.reservationId,
        amount: _folio!.balance,
      );
      await widget.client.processPayment(
        reservationId: _folio!.reservationId,
        amount: _folio!.balance,
      );
      // ignore: unused_local_variable (auth result kept for audit trace)
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

  Future<void> _completeCheckout() async {
    if (_folio == null) return;
    setState(() => _loading = true);
    try {
      await widget.client.kioskCheckOut(
        widget.propertyId,
        _folio!.reservationId,
        KioskCheckOut(
          roomNumber: _folio!.roomNumber,
          lastName: _lastNameController.text.trim().isEmpty
              ? null
              : _lastNameController.text.trim(),
          printReceipt: _printReceipt,
          emailReceipt: _emailReceipt,
          email: _emailReceipt && _emailController.text.trim().isNotEmpty
              ? _emailController.text.trim()
              : null,
        ),
      );
      if (_emailReceipt && _emailController.text.trim().isNotEmpty) {
        await widget.client.emailReceipt(
          to: _emailController.text.trim(),
          folioId: _folio!.id,
        );
      }
      if (mounted) {
        setState(() {
          _checkedOut = true;
          _loading = false;
        });
      }
    } on BffException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-out failed: ${e.message}')),
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
        title: const Text('Self Check-Out'),
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
                      onPressed: _loading ? null : _findFolio,
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
                        _loading ? 'Searching...' : 'Find Folio',
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    )
                  else if (_step == 1)
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
                        _folio != null && _folio!.balance > 0
                            ? 'Pay ${_folio!.currencyCode} ${_folio!.balance.toStringAsFixed(2)}'
                            : 'Continue',
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    )
                  else if (_step == 2)
                    FilledButton.icon(
                      onPressed: _loading ? null : _completeCheckout,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        _loading ? 'Processing...' : 'Complete Check-Out',
                        style: const TextStyle(fontSize: 20),
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

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepIdentify(
          roomNumberController: _roomNumberController,
          lastNameController: _lastNameController,
        );
      case 1:
        return _StepFolio(folio: _folio);
      case 2:
        return _StepPaymentResult(
          folio: _folio,
          paymentDone: _paymentDone,
          checkedOut: _checkedOut,
        );
      case 3:
        return _StepReceipt(
          folio: _folio,
          printReceipt: _printReceipt,
          emailReceipt: _emailReceipt,
          emailController: _emailController,
          onTogglePrint: (v) => setState(() => _printReceipt = v),
          onToggleEmail: (v) => setState(() => _emailReceipt = v),
          checkedOut: _checkedOut,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _StepIdentify extends StatelessWidget {
  const _StepIdentify({
    required this.roomNumberController,
    required this.lastNameController,
  });
  final TextEditingController roomNumberController;
  final TextEditingController lastNameController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Identify Your Room',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your room number to retrieve your folio.',
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: roomNumberController,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 24),
          decoration: InputDecoration(
            labelText: 'Room Number',
            labelStyle: const TextStyle(fontSize: 18),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.meeting_room, size: 32),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: lastNameController,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 24),
          decoration: InputDecoration(
            labelText: 'Last Name (optional)',
            labelStyle: const TextStyle(fontSize: 18),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person, size: 32),
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
                Icon(Icons.nfc, size: 32, color: Colors.blue),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'You can also tap your key card on the reader to identify your room.',
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

class _StepFolio extends StatelessWidget {
  const _StepFolio({required this.folio});
  final KioskFolio? folio;

  @override
  Widget build(BuildContext context) {
    if (folio == null) {
      return const Center(child: Text('No folio loaded.'));
    }
    final f = folio!;
    final fmt = DateFormat('MMM d');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Folio - Room ${f.roomNumber}',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Guest: ${f.guestName}',
          style: TextStyle(fontSize: 20, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Charges',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (f.charges.isEmpty)
                  const Text('No charges.')
                else
                  ...f.charges.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            fmt.format(item.date),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.description,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          Text(
                            '${item.currencyCode} ${item.amount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 24),
                const Text(
                  'Payments',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (f.payments.isEmpty)
                  const Text('No payments.')
                else
                  ...f.payments.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            fmt.format(item.date),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.description,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          Text(
                            '${item.currencyCode} ${item.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(height: 24),
                _BigRow(
                  'Total Charges',
                  '${f.currencyCode} ${f.totalCharges.toStringAsFixed(2)}',
                ),
                _BigRow(
                  'Balance Due',
                  '${f.currencyCode} ${f.balance.toStringAsFixed(2)}',
                  bold: true,
                  color: f.balance > 0 ? Colors.red : Colors.green,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BigRow extends StatelessWidget {
  const _BigRow(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

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
              fontSize: bold ? 24 : 18,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPaymentResult extends StatelessWidget {
  const _StepPaymentResult({
    required this.folio,
    required this.paymentDone,
    required this.checkedOut,
  });
  final KioskFolio? folio;
  final bool paymentDone;
  final bool checkedOut;

  @override
  Widget build(BuildContext context) {
    if (folio != null && folio!.balance <= 0) {
      return _ResultView(
        icon: Icons.check_circle,
        color: Colors.green,
        title: 'No Balance Due',
        message: 'Your folio is settled. Proceed to check-out.',
      );
    }
    if (paymentDone) {
      return _ResultView(
        icon: Icons.check_circle,
        color: Colors.green,
        title: 'Payment Confirmed',
        message: '${folio!.currencyCode} ${folio!.balance.toStringAsFixed(2)} '
            'has been charged successfully.',
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
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(Icons.payment, size: 72, color: Colors.green),
                const SizedBox(height: 16),
                const Text(
                  'Tap, Insert, or Swipe Your Card',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (folio != null)
                  Text(
                    'Amount Due: ${folio!.currencyCode} ${folio!.balance.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'The payment terminal is active. Follow the prompts to complete payment.',
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

class _StepReceipt extends StatelessWidget {
  const _StepReceipt({
    required this.folio,
    required this.printReceipt,
    required this.emailReceipt,
    required this.emailController,
    required this.onTogglePrint,
    required this.onToggleEmail,
    required this.checkedOut,
  });

  final KioskFolio? folio;
  final bool printReceipt;
  final bool emailReceipt;
  final TextEditingController emailController;
  final ValueChanged<bool> onTogglePrint;
  final ValueChanged<bool> onToggleEmail;
  final bool checkedOut;

  @override
  Widget build(BuildContext context) {
    if (checkedOut) {
      return _ResultView(
        icon: Icons.check_circle,
        color: Colors.green,
        title: 'Check-Out Complete!',
        message:
            'Thank you for staying with us, ${folio?.guestName ?? "Guest"}!\n'
            'Please deposit your key cards in the box.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Receipt',
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
                const Text(
                  'How would you like your receipt?',
                  style: TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: printReceipt,
                  onChanged: (v) => onTogglePrint(v ?? false),
                  title: const Text(
                    'Printed Receipt',
                    style: TextStyle(fontSize: 18),
                  ),
                  subtitle: const Text('Print at the kiosk'),
                  secondary: const Icon(Icons.print, size: 32),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.all(8),
                ),
                CheckboxListTile(
                  value: emailReceipt,
                  onChanged: (v) => onToggleEmail(v ?? false),
                  title: const Text(
                    'Email Receipt',
                    style: TextStyle(fontSize: 18),
                  ),
                  subtitle: const Text('Send to your email'),
                  secondary: const Icon(Icons.email, size: 32),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.all(8),
                ),
                if (emailReceipt) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Signature pad placeholder
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Digital Signature', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 8),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Sign here',
                      style: TextStyle(color: Colors.grey, fontSize: 24),
                    ),
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

class _ResultView extends StatelessWidget {
  const _ResultView({
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
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
