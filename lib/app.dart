import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'theme/app_theme.dart';

class VaultlineApp extends ConsumerWidget {
  const VaultlineApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Vaultline',
      debugShowCheckedModeBanner: false,
      theme: VTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
