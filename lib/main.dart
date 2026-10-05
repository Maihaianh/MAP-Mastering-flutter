import 'package:flutter/material.dart';
import 'engine.dart';
import 'home_page.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final eng = Engine();
  await eng.init();
  runApp(MapApp(eng));
}

class MapApp extends StatelessWidget {
  final Engine eng;
  const MapApp(this.eng, {super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'M.A.P Mastering',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: C.bg),
        home: HomePage(eng),
      );
}
