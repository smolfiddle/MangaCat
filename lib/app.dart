import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/pin/lock_screen.dart';
import 'features/pin/pin_setup_screen.dart';
import 'features/tracker/tracker_screen.dart';
import 'state/pin_controller.dart';
import 'state/providers.dart';
import 'state/tracker_controller.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class MangaCatApp extends StatelessWidget {
  const MangaCatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MangaCat',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      home: const RootGate(),
    );
  }
}

class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> with WidgetsBindingObserver {
  bool _everUnlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (ref.read(settingsStoreProvider).relockOnBackground) {
        ref.read(pinControllerProvider.notifier).lock();
      }
    } else if (state == AppLifecycleState.resumed) {
      _checkExternal();
    }
  }

  void _snack(String message) {
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _checkExternal() async {
    if (ref.read(pinControllerProvider) is! PinUnlocked) return;
    final controller = ref.read(trackerControllerProvider.notifier);
    if (!controller.isOpen) return;
    try {
      final result = await controller.checkExternal();
      if (result != ExternalCheckResult.conflict) return;
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final load = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('The CSV changed outside the app.'),
          content: const Text(
            'Load the file (external changes win) or keep your unsaved edits?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep my edits'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Load file'),
            ),
          ],
        ),
      );
      if (load == null) return;
      if (load) {
        await controller.reloadFromCsv();
        _snack('Reloaded from file.');
      } else {
        await controller.acceptExternalState();
        _snack('Keeping your edits. Save to CSV to update the file.');
      }
    } catch (_) {
      // The list may have been closed while the app was away.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PinGateState>(pinControllerProvider, (PinGateState? previous, PinGateState next) {
      if (next is PinUnlocked && previous is! PinUnlocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkExternal());
      }
    });

    final gate = ref.watch(pinControllerProvider);
    if (gate is PinSetupRequired) {
      return const PinSetupScreen();
    }
    if (gate is PinUnlocked) {
      _everUnlocked = true;
    }
    if (!_everUnlocked) {
      return const LockScreen();
    }
    return Stack(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        const MainShell(),
        if (gate is PinLocked) const LockScreen(),
      ],
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<void>(
      onPopWithResult: (void result) {
        final navigator = _navKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        }
      },
      child: Navigator(
        key: _navKey,
        onGenerateInitialRoutes: (NavigatorState navigator, String initialRoute) {
          final routes = <Route<dynamic>>[
            MaterialPageRoute<void>(
              builder: (_) => const HomeScreen(),
              settings: const RouteSettings(name: 'home'),
            ),
          ];
          final last = ref.read(recentsStoreProvider).last;
          if (last != null) {
            routes.add(
              MaterialPageRoute<void>(
                builder: (_) => TrackerScreen(uri: last.uri, name: last.name),
                settings: const RouteSettings(name: 'tracker'),
              ),
            );
          }
          return routes;
        },
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          builder: (_) => const HomeScreen(),
        ),
      ),
    );
  }
}
