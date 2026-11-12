import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'design.dart';
import 'shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: const Color(0xFF09080E),
  ));
  final state = AppState();
  await state.init();
  runApp(AthanaApp(state: state));
}

class AthanaApp extends StatelessWidget {
  final AppState state;
  const AthanaApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (BuildContext context, Widget? _) {
        final accent = Color(kAccents[state.prefs.accent]);
        final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
          surfaceContainerHigh: kSheet,
          surfaceContainerLow: kSheet,
        );
        return MaterialApp(
          title: 'Athana Melody',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: scheme,
            scaffoldBackgroundColor: kBg,
            appBarTheme: const AppBarTheme(backgroundColor: kPanel, surfaceTintColor: Colors.transparent),
            popupMenuTheme: PopupMenuThemeData(color: kSheet, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF2A2833),
              contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white70),
              trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) => s.contains(WidgetState.selected) ? lighter(accent) : Colors.white.withAlpha(26)),
              trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) => s.contains(WidgetState.selected) ? Colors.transparent : Colors.white.withAlpha(51)),
            ),
          ),
          builder: (BuildContext context, Widget? child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(state.prefs.textScale / 100)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: Shell(state: state),
        );
      },
    );
  }
}
