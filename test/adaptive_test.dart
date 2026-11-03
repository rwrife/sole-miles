import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sole_miles/data/mileage_repository.dart';
import 'package:sole_miles/domain/mileage.dart';
import 'package:sole_miles/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platforms = <TargetPlatform, String>{
    TargetPlatform.iOS: 'ios',
    TargetPlatform.android: 'android',
    TargetPlatform.windows: 'windows',
  };
  final sizes = <String, Size>{
    'phone': const Size(390, 844),
    'tablet': const Size(1024, 768),
    'desktop': const Size(1440, 900),
  };

  for (final entry in platforms.entries) {
    for (final size in sizes.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${entry.value} ${size.key} scale $scale chrome and rotation',
          (tester) async {
            final temp = Directory.systemTemp.createTempSync(
              'sole_miles_adaptive_',
            );
            final repo = SqliteMileageRepository.openAt(temp);
            repo.saveGear(
              GearItem(
                id: '00000000-0000-4000-8000-000000000001',
                name: 'Daily pair',
                category: 'running',
                retireMeters: 500000,
              ),
            );
            repo.saveActivities([
              Activity(
                id: '00000000-0000-4000-8000-000000000002',
                atUtc: DateTime.now().toUtc(),
                gearIds: ['00000000-0000-4000-8000-000000000001'],
                meters: 10000,
              ),
            ]);
            tester.view.physicalSize = size.value;
            tester.view.devicePixelRatio = 1;
            tester.view.platformDispatcher.textScaleFactorTestValue = scale;
            debugDefaultTargetPlatformOverride = entry.key;
            try {
              await tester.pumpWidget(SoleMilesApp(repository: repo));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.byType(AdaptiveNavigation), findsOneWidget);
              switch (entry.key) {
                case TargetPlatform.iOS:
                  expect(
                    find.byType(cupertino.CupertinoPageScaffold),
                    findsOneWidget,
                  );
                  expect(find.byType(material.Scaffold), findsNothing);
                case TargetPlatform.windows:
                  expect(find.byType(fluent.NavigationView), findsOneWidget);
                  expect(find.byType(material.Scaffold), findsNothing);
                case TargetPlatform.android:
                  expect(find.byType(material.Scaffold), findsOneWidget);
                  expect(
                    find.byType(cupertino.CupertinoPageScaffold),
                    findsNothing,
                  );
                default:
                  fail('unsupported platform');
              }
              expect(find.text('Status: Healthy'), findsOneWidget);
              if (entry.key == TargetPlatform.windows && size.key == 'phone') {
                await tester.tap(find.byIcon(fluent.FluentIcons.view).first);
              } else {
                await tester.tap(find.text('Rotation').first);
              }
              await tester.pumpAndSettle();
              expect(
                find.text('Daily pair: 10.0 km last 4 weeks'),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              // Cross-host font rasterization differs; pixels pinned on Linux only.
              if (Platform.isLinux) {
                await expectLater(
                  find.byType(SoleMilesApp),
                  matchesGoldenFile(
                    'goldens/${entry.value}_${size.key}_${scale.toInt()}.png',
                  ),
                );
              }
            } finally {
              await tester.pumpWidget(const SizedBox());
              debugDefaultTargetPlatformOverride = null;
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              tester.view.platformDispatcher.clearTextScaleFactorTestValue();
              repo.close();
              temp.deleteSync(recursive: true);
            }
          },
        );
      }
    }
  }
}
