import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/vault_door.dart';

/// Shown for a moment while the vault state is read from secure storage, or
/// if that read fails.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vaultControllerProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VaultDoor(state: VaultDoorState.locked, size: 140),
            if (status.hasError) ...[
              const SizedBox(height: VSpace.lg),
              Text('Couldn’t open secure storage', style: t.titleMedium),
              const SizedBox(height: VSpace.sm),
              TextButton(onPressed: () => ref.invalidate(vaultControllerProvider), child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
