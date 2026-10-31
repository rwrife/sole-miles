import 'package:flutter/widgets.dart';

void main() => runApp(const SoleMilesApp());

/// Neutral scaffold until platform-specific navigation ships in issue #5.
class SoleMilesApp extends StatelessWidget {
  const SoleMilesApp({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF254F43),
    builder: (context, child) => const Center(
      child: Text('Sole Miles', textDirection: TextDirection.ltr),
    ),
  );
}
