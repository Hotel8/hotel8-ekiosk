// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Hotel8:EKiosk
// SPDX-License-Identifier: Apache-2.0

// eKiosk app smoke test.
//
// Pumps the real root widget (`HkioskApp`) on a **kiosk-sized surface**
// (1920×1080 portrait tablet) and asserts the kiosk home screen renders its
// branding and the main service actions. The default test viewport (800×600)
// is smaller than the kiosk layout's design target and overflows the action
// tiles — a kiosk runs on a large fixed display, so the test pins that size.
//
// The kiosk is a single-page flow — no navigation shell, no network on the
// first frame.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ekiosk/app.dart';

void main() {
  testWidgets('HkioskApp renders kiosk home with service actions', (
    tester,
  ) async {
    // Kiosk display surface (portrait tablet) — the layout target.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const HkioskApp());
    await tester.pump(const Duration(milliseconds: 100));

    // Branding headline + guidance line.
    expect(find.text('Welcome to Sentin8 Hotel'), findsOneWidget);
    expect(find.text('Select a service to begin'), findsOneWidget);

    // Primary service actions.
    expect(find.text('Print Boarding Pass'), findsOneWidget);
  });
}
