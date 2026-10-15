// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

/// Kiosk Home.
///
/// Large touch-friendly home screen with three big buttons: Check In,
/// Check Out, Collect Your Key. Full-screen kiosk mode with no bottom
/// navigation.

import 'package:flutter/material.dart';

import '../bff_client.dart';
import '../models.dart';
import 'walk_in_search_page.dart';
import 'self_check_in_page.dart';
import 'self_check_out_page.dart';
import 'boarding_pass_page.dart';

class KioskHomePage extends StatelessWidget {
  const KioskHomePage({
    super.key,
    required this.client,
    required this.propertyId,
    this.propertyName,
    this.config = const KioskConfig(),
  });

  final BffClient client;

  /// Property the terminal serves (from the App runtime context).
  final String propertyId;

  /// Optional display name override for branding.
  final String? propertyName;

  /// Terminal config from the property's `kiosk-config` row — the mode-menu
  /// source of truth (ekiosk/DESIGN.md §3). Disabled modes do not render.
  final KioskConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Property branding
                  Icon(
                    Icons.hotel,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    propertyName ?? 'Welcome',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select a service to begin',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 48),
                  // Main buttons
                  Row(
                    children: [
                      Expanded(
                        child: _KioskHomeButton(
                          icon: Icons.login,
                          label: 'Check In',
                          subtitle: 'Retrieve reservation',
                          color: Colors.green,
                          enabled: config.allows('CHECK_IN'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SelfCheckInPage(
                                client: client,
                                propertyId: propertyId,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: _KioskHomeButton(
                          icon: Icons.logout,
                          label: 'Check Out',
                          subtitle: 'Settle & depart',
                          color: Colors.red,
                          enabled: config.allows('CHECK_OUT'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SelfCheckOutPage(
                                client: client,
                                propertyId: propertyId,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: _KioskHomeButton(
                      icon: Icons.key,
                      label: 'Collect Your Key',
                      subtitle: 'Already checked in online? Pick up your key',
                      color: Colors.blue,
                      height: 140,
                      enabled: config.allows('COLLECT_KEY'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SelfCheckInPage(
                            client: client,
                            propertyId: propertyId,
                            mode: KioskMode.collectKey,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: _KioskHomeButton(
                      icon: Icons.search,
                      label: 'Walk-In Availability',
                      subtitle: 'No reservation? Find a room now',
                      color: Colors.deepPurple,
                      height: 120,
                      enabled: config.allows('WALK_IN'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WalkInSearchPage(
                            client: client,
                            propertyId: propertyId,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Footer — a Wrap so the items flow instead of
                  // overflowing on narrow layouts.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BoardingPassPage(
                              client: client,
                              propertyId: propertyId,
                              reservationId: '',
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.flight),
                        label: const Text('Print Boarding Pass'),
                      ),
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.language),
                        label: const Text('Language: English'),
                      ),
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _currentTime(),
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _currentTime() {
    final now = DateTime.now();
    String hour(int h) => h > 12
        ? '${h - 12}'
        : h == 0
            ? '12'
            : '$h';
    final h = hour(now.hour);
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

class _KioskHomeButton extends StatelessWidget {
  const _KioskHomeButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.onTap,
    this.height = 200,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final double height;

  /// Config-gated mode: disabled modes render greyed-out (never hidden — the
  /// guest sees the service exists but is unavailable on this terminal).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(20),
      color: enabled ? null : Theme.of(context).disabledColor,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: height,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withValues(alpha: 0.8)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon shrinks with the tile so the content always fits the
              // fixed tile height (kiosk tiles are 120/140 px).
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Icon(icon, size: 56, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
