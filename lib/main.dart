import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:encrypted_files/core/di.dart';
import 'package:encrypted_files/core/theme.dart';
import 'package:encrypted_files/ui/providers/app_state.dart';
import 'package:encrypted_files/ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDi.init();
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: AppDi.appState,
      child: const EncryptedFilesApp(),
    ),
  );
}

class EncryptedFilesApp extends StatelessWidget {
  const EncryptedFilesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return MaterialApp(
          title: 'EncryptedFiles',
          debugShowCheckedModeBanner: false,
          theme: AppThemes.light(),
          darkTheme: AppThemes.dark(),
          themeMode: state.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
          home: const HomeScreen(),
        );
      },
    );
  }
}
