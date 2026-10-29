// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'package:sentin8/sentin8.dart';

import 'bff_client.dart';
import 'models.dart';
import 'screens/kiosk_home_page.dart';

export 'screens/kiosk_home_page.dart';
export 'screens/walk_in_search_page.dart';
export 'screens/self_check_in_page.dart';
export 'screens/self_check_out_page.dart';
export 'screens/boarding_pass_page.dart';

class HkioskApp extends StatelessWidget {
  const HkioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hkiosk - Self Check-in',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
        // Larger default text and touch targets for kiosk mode
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18),
          bodyMedium: TextStyle(fontSize: 16),
          titleLarge: TextStyle(fontSize: 24),
          titleMedium: TextStyle(fontSize: 20),
          headlineMedium: TextStyle(fontSize: 32),
        ),
      ),
      home: const HkioskRoot(),
    );
  }
}

/// Root widget - bootstraps the BFF client and shows the full-screen
/// kiosk home. No bottom navigation (kiosk mode). The kiosk uses a
/// limited-scope OAuth client - no guest login.
class HkioskRoot extends StatefulWidget {
  const HkioskRoot({super.key});

  @override
  State<HkioskRoot> createState() => _HkioskRootState();
}

class _HkioskRootState extends State<HkioskRoot> {
  BffClient? _client;
  AppRuntimeContext? _runtimeContext;
  KioskConfig _config = const KioskConfig();
  String? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Same-origin bootstrap - the TLS proxy injects the X-Sentin8-*
      // headers the runtime context resolves from (ekiosk/DESIGN.md §2).
      final ctx = await fetchRuntimeContext(appBaseUrl: '');
      // The kiosk serves the property whose environment hosts the terminal.
      // The check-out/check-in flows take the property id from this context.
      final client = BffClient(baseUrl: ctx.bffBaseUrl);
      // Terminal config read (ekiosk/DESIGN.md §3): the property's kiosk-config
      // row is the mode-menu source of truth - `lockdown=true` freezes the
      // terminal at the attract loop; disabled modes are not offered.
      KioskConfig config = const KioskConfig();
      try {
        config = await client.getKioskConfig(ctx.environmentId);
      } on BffException {
        // Config unavailable → defaults (never invent modes server-side).
      }
      setState(() {
        _runtimeContext = ctx;
        _client = client;
        _config = config;
      });
    } catch (e) {
      setState(() => _bootstrapError = e.toString());
    }
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapError != null) {
      return Scaffold(
        body: Center(
          child: Text(
            'Kiosk unavailable: $_bootstrapError',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }
    final client = _client;
    final ctx = _runtimeContext;
    if (client == null || ctx == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_config.lockdown) {
      // Lockdown freeze (ekiosk/DESIGN.md §3): the terminal sticks at the
      // attract loop with a staff-unlock notice - no guest journeys render.
      return _LockdownScreen(propertyName: ctx.instanceName);
    }
    return KioskHomePage(
      client: client,
      propertyId: ctx.environmentId,
      propertyName: ctx.instanceName.isNotEmpty ? ctx.instanceName : null,
      config: _config,
    );
  }
}

/// Lockdown freeze screen - the attract loop with a staff-unlock notice.
class _LockdownScreen extends StatelessWidget {
  const _LockdownScreen({required this.propertyName});

  final String propertyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 96,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(propertyName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Terminal temporarily unavailable.'),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed:
                  () {}, // staff unlock rides the deployment platform's auth
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Staff unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
