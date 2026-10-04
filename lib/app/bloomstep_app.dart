import 'package:flutter/material.dart';

import '../features/garden/garden_screen.dart';
import 'theme.dart';

class BloomstepApp extends StatelessWidget {
  const BloomstepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bloomstep',
      debugShowCheckedModeBanner: false,
      theme: BloomstepTheme.light(),
      darkTheme: BloomstepTheme.dark(),
      home: const GardenScreen(),
    );
  }
}
