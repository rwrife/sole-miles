import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;

import 'package:flutter/widgets.dart' show Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:sole_miles/data/mileage_repository.dart';
import 'package:sole_miles/domain/mileage.dart';
import 'package:sole_miles/main.dart';

void main() {
  late Directory tempDir;
  late SqliteMileageRepository repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sole_miles_ui_test_');
    repo = SqliteMileageRepository.openAt(tempDir);
  });

  tearDown(() {
    repo.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('adds gear item with validation and unit toggle', (tester) async {
    await tester.pumpWidget(SoleMilesApp(repository: repo));
    await tester.pumpAndSettle();

    // 1. Open add gear form
    await tester.tap(find.text('Add gear'));
    await tester.pumpAndSettle();

    // 2. Validate empty submission rejected inline
    await tester.tap(find.text('Save gear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check name, category'), findsWidgets);

    // 3. Fill valid details
    await tester.enterText(
      find.widgetWithText(AdaptiveInput, 'Name'),
      'Ghost 15',
    );
    await tester.enterText(
      find.widgetWithText(AdaptiveInput, 'Brand / model'),
      'Brooks',
    );
    await tester.enterText(
      find.widgetWithText(AdaptiveInput, 'Category'),
      'road',
    );
    await tester.enterText(
      find.widgetWithText(AdaptiveInput, 'Retire target'),
      '600',
    );
    await tester.tap(find.text('Save gear'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ghost 15 — 0.0 / 600.0 km'), findsOneWidget);
    expect(repo.gear.length, 1);
    expect(repo.gear.first.name, 'Ghost 15');
    expect(repo.gear.first.retireMeters, 600000);
  });

  testWidgets(
    'logs activity against gear, verifies odometer and last-used update',
    (tester) async {
      final shoe = GearItem(
        id: newId(),
        name: 'Pegasus 40',
        brand: 'Nike',
        category: 'running',
        retireMeters: 500000,
      );
      repo.saveGear(shoe);

      await tester.pumpWidget(SoleMilesApp(repository: repo));
      await tester.pumpAndSettle();

      // Open activity form
      await tester.tap(find.text('Log activity'));
      await tester.pumpAndSettle();

      // Enter date and distance
      await tester.enterText(
        find.widgetWithText(AdaptiveInput, 'Date YYYY-MM-DD'),
        '2026-11-02',
      );
      await tester.enterText(
        find.widgetWithText(AdaptiveInput, 'Distance (kilometers)'),
        '10.5',
      );
      await tester.enterText(
        find.widgetWithText(AdaptiveInput, 'Feel note (optional)'),
        'Smooth recovery run',
      );
      await tester.tap(find.text('Save activity'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Pegasus 40 — 10.5 / 500.0 km'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Last used: 2026-11-02'), 50.0);
      expect(find.text('Last used: 2026-11-02'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('2026-11: 10.5 km'),
        50.0,
      );
      expect(find.textContaining('2026-11: 10.5 km'), findsOneWidget);
      expect(repo.activities.length, 1);
      expect(repo.activities.first.meters, 10500);
    },
  );

  testWidgets('deletes activity with undo restoring ledger state', (
    tester,
  ) async {
    final shoe = GearItem(
      id: newId(),
      name: 'Vaporfly',
      brand: 'Nike',
      category: 'race',
      retireMeters: 250000,
    );
    repo.saveGear(shoe);
    final act = Activity(
      id: newId(),
      atUtc: DateTime.utc(2026, 11, 1),
      gearIds: [shoe.id],
      meters: 21100,
      note: 'Half marathon',
    );
    repo.saveActivities([act]);

    await tester.pumpWidget(SoleMilesApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vaporfly — 21.1 / 250.0 km'), findsOneWidget);

    // Delete
    await tester.scrollUntilVisible(
      find.text('Delete activity ${act.id}'),
      150.0,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete activity ${act.id}'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Activity deleted'), -150.0);
    await tester.pumpAndSettle();
    expect(find.text('Activity deleted'), findsOneWidget);
    expect(find.textContaining('Vaporfly — 0.0 / 250.0 km'), findsOneWidget);
    expect(repo.activities, isEmpty);

    // Undo
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Vaporfly — 21.1 / 250.0 km'), findsOneWidget);
    expect(repo.activities.length, 1);
  });

  testWidgets(
    'retires gear item and hides from default view unless show retired toggled',
    (tester) async {
      final oldPair = GearItem(
        id: newId(),
        name: 'Old Speedgoat',
        brand: 'Hoka',
        category: 'trail',
        retireMeters: 700000,
      );
      final newPair = GearItem(
        id: newId(),
        name: 'Speedgoat 5',
        brand: 'Hoka',
        category: 'trail',
        retireMeters: 700000,
      );
      repo.saveGear(oldPair);
      repo.saveGear(newPair);

      await tester.pumpWidget(SoleMilesApp(repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('Old Speedgoat — 0.0 / 700.0 km'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Replace Old Speedgoat with Speedgoat 5'),
        150.0,
      );
      await tester.pumpAndSettle();
      // Retire old pair and link new pair as successor
      await tester.tap(find.text('Replace Old Speedgoat with Speedgoat 5'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Old Speedgoat retired'),
        -150.0,
      );
      await tester.pumpAndSettle();
      expect(find.text('Old Speedgoat retired'), findsOneWidget);
      // Old pair is retired, header line hidden by default
      expect(find.text('Old Speedgoat — 0.0 / 700.0 km'), findsNothing);
      expect(
        find.textContaining('Speedgoat 5 — 0.0 / 700.0 km'),
        findsOneWidget,
      );

      // Toggle show retired
      await tester.tap(find.text('Show retired'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Old Speedgoat — 0.0 / 700.0 km (retired)'),
        findsOneWidget,
      );

      // Verify successor saved in DB
      final archived = repo.gear.firstWhere((g) => g.id == oldPair.id);
      expect(archived.archived, isTrue);
      expect(archived.successorId, newPair.id);
    },
  );

  testWidgets('photo picker saves copy in private gear storage', (
    tester,
  ) async {
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00];
    await tester.pumpWidget(
      SoleMilesApp(
        repository: repo,
        pickPhoto: ({List<XTypeGroup> acceptedTypeGroups = const []}) async =>
            XFile.fromData(Uint8List.fromList(png), name: 'shoe_sample.png'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add gear'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(AdaptiveInput, 'Name'),
      'Mach 6',
    );
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Photo: saved'),
      findsOneWidget,
      reason:
          'photo picker error: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).where((e) => e != null).join(' | ')}',
    );
    await tester.tap(find.text('Save gear'));
    await tester.pumpAndSettle();
    expect(repo.photoPath(repo.gear.first.id), isNotNull);
  });
}
