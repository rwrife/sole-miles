import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'data/mileage_repository.dart';
import 'domain/mileage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await SqliteMileageRepository.openPrivate();
  runApp(SoleMilesApp(repository: repository));
}

enum AppPlatform { ios, android, windows }

AppPlatform get appPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.iOS => AppPlatform.ios,
  TargetPlatform.windows => AppPlatform.windows,
  _ => AppPlatform.android,
};

// ponytail: one chrome seam; macOS/Linux use their host convention until supported.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({required this.title, required this.child, super.key});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (appPlatform) {
    AppPlatform.ios => cupertino.CupertinoPageScaffold(
      navigationBar: cupertino.CupertinoNavigationBar(middle: Text(title)),
      child: SafeArea(child: child),
    ),
    AppPlatform.windows => fluent.ScaffoldPage(
      header: fluent.PageHeader(title: Text(title)),
      content: SafeArea(child: child),
    ),
    AppPlatform.android => material.Scaffold(
      appBar: material.AppBar(title: Text(title)),
      body: SafeArea(child: child),
    ),
  };
}

// ponytail: two destinations only; add a router when screens gain deep links.
class AdaptiveNavigation extends StatelessWidget {
  const AdaptiveNavigation({
    required this.selected,
    required this.onChanged,
    required this.ledger,
    required this.rotation,
    super.key,
  });
  final int selected;
  final ValueChanged<int> onChanged;
  final Widget ledger;
  final Widget rotation;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final body = selected == 0 ? ledger : rotation;
    if (appPlatform == AppPlatform.windows) {
      return fluent.NavigationView(
        pane: fluent.NavigationPane(
          selected: selected,
          onChanged: onChanged,
          displayMode: wide
              ? fluent.PaneDisplayMode.expanded
              : fluent.PaneDisplayMode.compact,
          items: [
            fluent.PaneItem(
              icon: const fluent.Icon(fluent.FluentIcons.home),
              title: const Text('Ledger'),
              body: ledger,
            ),
            fluent.PaneItem(
              icon: const fluent.Icon(fluent.FluentIcons.view),
              title: const Text('Rotation'),
              body: rotation,
            ),
          ],
        ),
      );
    }
    if (appPlatform == AppPlatform.ios) {
      if (wide) {
        return Row(
          children: [
            SizedBox(
              width: 180,
              child: Column(
                children: [
                  cupertino.CupertinoButton(
                    onPressed: () => onChanged(0),
                    child: const Text('Ledger'),
                  ),
                  cupertino.CupertinoButton(
                    onPressed: () => onChanged(1),
                    child: const Text('Rotation'),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: body),
          cupertino.CupertinoTabBar(
            currentIndex: selected,
            onTap: onChanged,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(cupertino.CupertinoIcons.list_bullet),
                label: 'Ledger',
              ),
              BottomNavigationBarItem(
                icon: Icon(cupertino.CupertinoIcons.chart_bar),
                label: 'Rotation',
              ),
            ],
          ),
        ],
      );
    }
    if (wide) {
      return Row(
        children: [
          material.NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: onChanged,
            labelType: material.NavigationRailLabelType.all,
            destinations: const [
              material.NavigationRailDestination(
                icon: Icon(material.Icons.list),
                label: Text('Ledger'),
              ),
              material.NavigationRailDestination(
                icon: Icon(material.Icons.bar_chart),
                label: Text('Rotation'),
              ),
            ],
          ),
          Expanded(child: body),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: body),
        material.NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: onChanged,
          destinations: const [
            material.NavigationDestination(
              icon: Icon(material.Icons.list),
              label: 'Ledger',
            ),
            material.NavigationDestination(
              icon: Icon(material.Icons.bar_chart),
              label: 'Rotation',
            ),
          ],
        ),
      ],
    );
  }
}

class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => switch (appPlatform) {
    AppPlatform.ios => cupertino.CupertinoButton.filled(
      onPressed: onPressed,
      child: Text(label),
    ),
    AppPlatform.windows => fluent.FilledButton(
      onPressed: onPressed,
      child: Text(label),
    ),
    AppPlatform.android => material.FilledButton(
      onPressed: onPressed,
      child: Text(label),
    ),
  };
}

class AdaptiveDialog extends StatelessWidget {
  const AdaptiveDialog({required this.title, required this.child, super.key});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => switch (appPlatform) {
    AppPlatform.ios => cupertino.CupertinoAlertDialog(
      title: Text(title),
      content: child,
    ),
    AppPlatform.windows => fluent.ContentDialog(
      title: Text(title),
      content: child,
    ),
    AppPlatform.android => material.AlertDialog(
      title: Text(title),
      content: child,
    ),
  };
}

class AdaptiveDatePicker {
  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    final state = appPlatform;
    if (state == AppPlatform.ios) {
      DateTime selected = initialDate;
      final ok = await cupertino.showCupertinoModalPopup<bool>(
        context: context,
        builder: (ctx) => Container(
          height: 260,
          color: cupertino.CupertinoColors.systemBackground.resolveFrom(ctx),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  cupertino.CupertinoButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  cupertino.CupertinoButton(
                    child: const Text('Done'),
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
              Expanded(
                child: cupertino.CupertinoDatePicker(
                  mode: cupertino.CupertinoDatePickerMode.date,
                  initialDateTime: initialDate,
                  minimumDate: firstDate,
                  maximumDate: lastDate,
                  onDateTimeChanged: (val) => selected = val,
                ),
              ),
            ],
          ),
        ),
      );
      return (ok ?? false) ? selected : null;
    }
    if (state == AppPlatform.windows) {
      DateTime selected = initialDate;
      final ok = await fluent.showDialog<bool>(
        context: context,
        builder: (ctx) => fluent.ContentDialog(
          title: const Text('Select date'),
          content: fluent.DatePicker(
            selected: selected,
            startDate: firstDate,
            endDate: lastDate,
            onChanged: (val) => selected = val,
          ),
          actions: [
            fluent.Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            fluent.FilledButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );
      return (ok ?? false) ? selected : null;
    }
    return material.showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }
}

class AdaptiveInput extends StatelessWidget {
  const AdaptiveInput({
    required this.label,
    required this.controller,
    this.error,
    this.onSubmitted,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final String? error;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      switch (appPlatform) {
        AppPlatform.ios => cupertino.CupertinoTextField(
          controller: controller,
          placeholder: label,
          onSubmitted: onSubmitted,
          padding: const EdgeInsets.all(12),
        ),
        AppPlatform.windows => fluent.TextBox(
          controller: controller,
          placeholder: label,
          onSubmitted: onSubmitted,
        ),
        AppPlatform.android => material.TextField(
          controller: controller,
          onSubmitted: onSubmitted,
          decoration: material.InputDecoration(
            hintText: label,
            errorText: error,
          ),
        ),
      },
      if (error != null && appPlatform != AppPlatform.android)
        Semantics(
          liveRegion: true,
          child: Text(error!, style: const TextStyle(color: Color(0xFFAF3028))),
        ),
    ],
  );
}

bool isSupportedPhoto(Uint8List bytes) =>
    (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) ||
    (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF);

String newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class SoleMilesApp extends StatelessWidget {
  const SoleMilesApp({this.repository, this.pickPhoto = openFile, super.key});
  final MileageRepository? repository;
  final Future<XFile?> Function({List<XTypeGroup> acceptedTypeGroups})
  pickPhoto;
  @override
  Widget build(BuildContext context) {
    final home = LedgerScreen(repository: repository, pickPhoto: pickPhoto);
    return switch (appPlatform) {
      AppPlatform.ios => cupertino.CupertinoApp(
        title: 'Sole Miles',
        home: home,
      ),
      AppPlatform.windows => fluent.FluentApp(title: 'Sole Miles', home: home),
      AppPlatform.android => material.MaterialApp(
        title: 'Sole Miles',
        theme: material.ThemeData(useMaterial3: true),
        home: home,
      ),
    };
  }
}

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({
    required this.repository,
    this.pickPhoto = openFile,
    super.key,
  });
  final MileageRepository? repository;
  final Future<XFile?> Function({List<XTypeGroup> acceptedTypeGroups})
  pickPhoto;
  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late final MileageRepository? repo = widget.repository;
  GearItem? editingGear;
  Activity? editingActivity;
  String? notice;
  Activity? pendingDelete;
  GearItem? pendingArchive;
  bool showArchived = false;
  int selectedPage = 0;
  final ledgerFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    ledgerFocus.requestFocus();
  }

  final name = TextEditingController();
  final brand = TextEditingController();
  final category = TextEditingController(text: 'running');
  final target = TextEditingController(text: '500');
  final distance = TextEditingController();
  final date = TextEditingController();
  final note = TextEditingController();
  String? formError;
  DistanceUnit unit = DistanceUnit.kilometers;
  String? selectedGearId;
  bool unknown = false;
  String? photoPath;

  @override
  void dispose() {
    ledgerFocus.dispose();
    for (final c in [name, brand, category, target, distance, date, note]) {
      c.dispose();
    }
    super.dispose();
  }

  void startGear([GearItem? item]) => setState(() {
    editingActivity = null;
    editingGear =
        item ??
        GearItem(id: newId(), category: 'running', retireMeters: 500000);
    name.text = item?.name ?? '';
    brand.text = item?.brand ?? '';
    category.text = item?.category ?? 'running';
    unit = item?.unit ?? DistanceUnit.kilometers;
    target.text = item == null
        ? '500'
        : Mileage.display(item.retireMeters, unit);
    formError = null;
    photoPath = null;
  });

  void startActivity([Activity? activity]) => setState(() {
    editingGear = null;
    editingActivity =
        activity ??
        Activity(id: newId(), atUtc: DateTime.now().toUtc(), gearIds: []);
    selectedGearId = activity?.gearIds.firstOrNull;
    final active = repo?.gear.where((g) => !g.archived).toList() ?? [];
    selectedGearId ??= active.firstOrNull?.id;
    unit =
        repo?.gear.where((g) => g.id == selectedGearId).firstOrNull?.unit ??
        DistanceUnit.kilometers;
    unknown = activity?.meters == null && activity != null;
    distance.text = activity?.meters == null
        ? ''
        : Mileage.display(activity!.meters!, unit);
    date.text = (activity?.atUtc ?? DateTime.now().toUtc())
        .toIso8601String()
        .substring(0, 10);
    note.text = activity?.note ?? '';
    formError = null;
  });

  void saveGear() {
    try {
      if (name.text.trim().isEmpty || category.text.trim().isEmpty) {
        throw const FormatException('Name and category required');
      }
      final item = GearItem(
        id: editingGear!.id,
        name: name.text.trim(),
        brand: brand.text.trim(),
        category: category.text.trim(),
        retireMeters: Mileage.fromDisplay(target.text, unit),
        unit: unit,
        archived: editingGear!.archived,
        successorId: editingGear!.successorId,
      );
      repo!.saveGear(item);
      setState(() {
        editingGear = null;
        formError = null;
      });
    } catch (e) {
      setState(() => formError = 'Check name, category and retire target: $e');
    }
  }

  void saveActivity() {
    try {
      final gear = repo!.gear.where((g) => g.id == selectedGearId).firstOrNull;
      if (gear == null ||
          (gear.archived && !editingActivity!.gearIds.contains(gear.id))) {
        throw const FormatException('Choose active gear');
      }
      final parts = date.text.split('-').map(int.parse).toList();
      if (parts.length != 3) {
        throw const FormatException('Date must be YYYY-MM-DD');
      }
      final day = DateTime.utc(parts[0], parts[1], parts[2]);
      if (day.year != parts[0] ||
          day.month != parts[1] ||
          day.day != parts[2]) {
        throw const FormatException('Invalid date');
      }
      repo!.saveActivities([
        Activity(
          id: editingActivity!.id,
          atUtc: day,
          gearIds: [gear.id],
          meters: unknown
              ? null
              : Mileage.fromDisplay(distance.text, gear.unit),
          note: note.text.trim(),
          category: gear.category,
        ),
      ]);
      setState(() {
        editingActivity = null;
        formError = null;
      });
    } catch (e) {
      setState(() => formError = 'Check date, gear and distance: $e');
    }
  }

  void archive(GearItem item, [GearItem? successor]) {
    repo!.saveGear(
      GearItem(
        id: item.id,
        category: item.category,
        name: item.name,
        brand: item.brand,
        unit: item.unit,
        retireMeters: item.retireMeters,
        archived: true,
        successorId: successor?.id,
      ),
    );
    setState(() {
      pendingArchive = item;
      notice = '${item.name} retired';
    });
  }

  void delete(Activity activity) {
    repo!.deleteActivity(activity.id);
    setState(() {
      pendingDelete = activity;
      notice = 'Activity deleted';
    });
  }

  void undo() {
    try {
      if (pendingDelete != null) repo!.saveActivities([pendingDelete!]);
      if (pendingArchive != null) repo!.saveGear(pendingArchive!);
      setState(() {
        pendingDelete = null;
        pendingArchive = null;
        notice = null;
      });
    } catch (e) {
      setState(() => notice = 'Undo failed: $e');
    }
  }

  Widget gearForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Gear item'),
      AdaptiveInput(label: 'Name', controller: name, error: formError),
      AdaptiveInput(label: 'Brand / model', controller: brand),
      AdaptiveInput(label: 'Category', controller: category, error: formError),
      AdaptiveInput(
        label: 'Retire target',
        controller: target,
        error: formError,
        onSubmitted: (_) => saveGear(),
      ),
      AdaptiveButton(
        label: 'Unit: ${unit.name}',
        onPressed: () => setState(() {
          unit = unit == DistanceUnit.kilometers
              ? DistanceUnit.miles
              : DistanceUnit.kilometers;
        }),
      ),
      AdaptiveButton(
        label: 'Choose photo',
        onPressed: () async {
          try {
            final photo = await widget.pickPhoto(
              acceptedTypeGroups: [
                const XTypeGroup(
                  label: 'Images',
                  extensions: ['png', 'jpg', 'jpeg'],
                ),
              ],
            );
            if (photo == null || !mounted) return;
            final bytes = await photo.readAsBytes();
            if (bytes.length > 10 * 1024 * 1024) {
              throw const FormatException('Photo too large');
            }
            if (!isSupportedPhoto(bytes)) {
              throw const FormatException('Only PNG and JPEG photos supported');
            }
            // Save after gear row exists; no source-gallery path enters database.
            if (name.text.trim().isEmpty || category.text.trim().isEmpty) {
              throw const FormatException('Save gear name and category first');
            }
            final item = GearItem(
              id: editingGear!.id,
              name: name.text.trim(),
              brand: brand.text.trim(),
              category: category.text.trim(),
              retireMeters: Mileage.fromDisplay(target.text, unit),
              unit: unit,
            );
            repo!.saveGear(item);
            (repo! as SqliteMileageRepository).savePhoto(item.id, bytes);
            setState(() => photoPath = 'saved');
          } catch (e) {
            if (mounted) setState(() => formError = 'Photo not saved: $e');
          }
        },
      ),
      if (photoPath != null) Text('Photo: $photoPath'),
      if (formError != null)
        Semantics(liveRegion: true, child: Text(formError!)),
      AdaptiveButton(label: 'Save gear', onPressed: saveGear),
      AdaptiveButton(
        label: 'Cancel',
        onPressed: () => setState(() => editingGear = null),
      ),
    ],
  );

  Widget activityForm() {
    final active = repo!.gear
        .where((g) => !g.archived || editingActivity!.gearIds.contains(g.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Activity'),
        AdaptiveInput(
          label: 'Date YYYY-MM-DD',
          controller: date,
          error: formError,
        ),
        AdaptiveButton(
          label: 'Pick date',
          onPressed: () async {
            final now = DateTime.now();
            final parsed = DateTime.tryParse(date.text);
            final picked = await AdaptiveDatePicker.show(
              context,
              initialDate: parsed ?? now,
              firstDate: DateTime(1900),
              lastDate: DateTime(now.year + 10),
            );
            if (picked != null && mounted) {
              setState(
                () => date.text = picked.toIso8601String().substring(0, 10),
              );
            }
          },
        ),
        for (final item in active)
          AdaptiveButton(
            label:
                '${selectedGearId == item.id ? 'Selected: ' : 'Wear: '}${item.name}',
            onPressed: item.archived
                ? null
                : () => setState(() {
                    selectedGearId = item.id;
                    unit = item.unit;
                  }),
          ),
        if (active.isEmpty) const Text('Add gear before logging activity.'),
        AdaptiveButton(
          label: unknown
              ? 'Distance unknown (change)'
              : 'Mark distance unknown',
          onPressed: () => setState(() => unknown = !unknown),
        ),
        if (!unknown)
          AdaptiveInput(
            label: 'Distance (${unit.name})',
            controller: distance,
            error: formError,
            onSubmitted: (_) => saveActivity(),
          ),
        AdaptiveInput(label: 'Feel note (optional)', controller: note),
        if (formError != null)
          Semantics(liveRegion: true, child: Text(formError!)),
        AdaptiveButton(label: 'Save activity', onPressed: saveActivity),
        AdaptiveButton(
          label: 'Cancel',
          onPressed: () => setState(() => editingActivity = null),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = repo?.gear.toList() ?? [];
    final activities = repo?.activities ?? [];
    items.sort((a, b) {
      final left = Mileage.odometer(a.id, activities) * b.retireMeters;
      final right = Mileage.odometer(b.id, activities) * a.retireMeters;
      return right.compareTo(left);
    });

    final rotationView = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '4-Week Rotation Balance',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 12),
        for (final item in items.where((g) => !g.archived)) ...[
          Builder(
            builder: (ctx) {
              final nowUtc = DateTime.now().toUtc();
              final map = Mileage.rotation(items, activities, nowUtc);
              final meters = map[item.id] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${item.name}: ${meters / 1000} km last 4 weeks'),
              );
            },
          ),
        ],
        if (items.where((g) => !g.archived).isEmpty)
          const Text('No active gear in rotation.'),
      ],
    );

    final ledgerView = Focus(
      focusNode: ledgerFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyN &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          startActivity();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (repo == null) const Text('Sole Miles'),
          if (repo != null) ...[
            if (notice != null)
              Row(
                children: [
                  Expanded(
                    child: Semantics(liveRegion: true, child: Text(notice!)),
                  ),
                  AdaptiveButton(label: 'Undo', onPressed: undo),
                ],
              ),
            if (editingGear != null)
              gearForm()
            else if (editingActivity != null)
              activityForm()
            else ...[
              AdaptiveButton(
                label: 'Log activity',
                onPressed: () => startActivity(),
              ),
              AdaptiveButton(label: 'Add gear', onPressed: () => startGear()),
              AdaptiveButton(
                label: showArchived ? 'Hide retired' : 'Show retired',
                onPressed: () => setState(() => showArchived = !showArchived),
              ),
              for (final item in items.where(
                (g) => !g.archived || showArchived,
              )) ...[
                Builder(
                  builder: (ctx) {
                    final odo = Mileage.odometer(item.id, activities);
                    final state = Mileage.wear(odo, item.retireMeters);
                    final (statusText, statusColor) = switch (state) {
                      WearState.healthy => ('Healthy', const Color(0xFF1B5E20)),
                      WearState.nudge => ('Nudge', const Color(0xFFE65100)),
                      WearState.retire => ('Retire', const Color(0xFFB71C1C)),
                    };
                    return Semantics(
                      label:
                          '${item.name} odometer ${odo / 1000} of ${item.retireMeters / 1000} kilometers, wear status $statusText',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.name.isEmpty ? item.category : item.name} — '
                            '${odo / 1000} / '
                            '${item.retireMeters / 1000} km'
                            '${item.archived ? ' (retired)' : ''}',
                          ),
                          Text(
                            'Status: $statusText',
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Text(
                  'Last used: ${activities.where((a) => a.gearIds.contains(item.id)).isEmpty ? 'Never' : (activities.where((a) => a.gearIds.contains(item.id)).map((a) => a.atUtc).toList()..sort()).last.toIso8601String().substring(0, 10)}',
                ),
                AdaptiveButton(
                  label: 'Edit ${item.name}',
                  onPressed: () => startGear(item),
                ),
                if (!item.archived) ...[
                  AdaptiveButton(
                    label: 'Retire ${item.name}',
                    onPressed: () => archive(item),
                  ),
                  for (final next in items.where(
                    (g) => !g.archived && g.id != item.id,
                  ))
                    AdaptiveButton(
                      label: 'Replace ${item.name} with ${next.name}',
                      onPressed: () => archive(item, next),
                    ),
                ],
                for (final month in <String>{
                  for (final a in activities.where(
                    (a) => a.gearIds.contains(item.id),
                  ))
                    a.atUtc.toIso8601String().substring(0, 7),
                })
                  Text(
                    '$month: ${activities.where((a) => a.gearIds.contains(item.id) && a.atUtc.toIso8601String().startsWith(month)).fold<int>(0, (sum, a) => sum + (a.meters ?? 0)) / 1000} km',
                  ),
              ],
              for (final activity in activities.reversed) ...[
                Text(
                  '${activity.atUtc.toIso8601String().substring(0, 10)}: '
                  '${activity.meters == null ? 'Unknown' : '${activity.meters! / 1000} km'} '
                  '${activity.note}',
                ),
                AdaptiveButton(
                  label: 'Edit activity ${activity.id}',
                  onPressed: () => startActivity(activity),
                ),
                AdaptiveButton(
                  label: 'Delete activity ${activity.id}',
                  onPressed: () => delete(activity),
                ),
              ],
            ],
          ],
        ],
      ),
    );

    return AdaptiveScaffold(
      title: 'Sole Miles',
      child: AdaptiveNavigation(
        selected: selectedPage,
        onChanged: (idx) => setState(() => selectedPage = idx),
        ledger: ledgerView,
        rotation: rotationView,
      ),
    );
  }
}
