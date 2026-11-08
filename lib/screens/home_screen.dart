import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../security/biometrics.dart';
import '../theme/app_theme.dart';

/// Inside the vault. Authenticator codes (stage 2) and passwords (stage 4)
/// will live here; for now it shows the empty vault and its settings.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget enter(Widget w, int ms) =>
        reduced ? w : w.animate().fadeIn(delay: ms.ms, duration: 400.ms).slideY(begin: 0.1, curve: Curves.easeOut);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: VSpace.sm),
              Row(
                children: [
                  Text('VAULTLINE', style: t.labelSmall?.copyWith(color: VColors.accent)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: VColors.surface,
                      showDragHandle: true,
                      builder: (_) => const _SettingsSheet(),
                    ),
                    icon: const Icon(Icons.tune_rounded, color: VColors.muted),
                  ),
                  IconButton(
                    key: const Key('lock-button'),
                    tooltip: 'Lock vault',
                    onPressed: () => ref.read(vaultControllerProvider.notifier).lock(),
                    icon: const Icon(Icons.lock_rounded, color: VColors.text),
                  ),
                ],
              ),
              const SizedBox(height: VSpace.md),
              enter(Text('Your vault', style: t.headlineMedium), 0),
              const Spacer(),
              Center(
                child: enter(
                  Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: VColors.raised,
                          border: Border.all(color: VColors.line),
                          boxShadow: [BoxShadow(color: VColors.accent.withValues(alpha: 0.18), blurRadius: 40)],
                        ),
                        child: const Icon(Icons.shield_moon_outlined, size: 42, color: VColors.accent),
                      ),
                      const SizedBox(height: VSpace.lg),
                      Text('Your vault is open and empty', style: t.titleMedium),
                      const SizedBox(height: VSpace.sm),
                      Text(
                        '2FA codes and passwords you add will be\nkept here, encrypted on this device.',
                        style: t.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  120,
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final kind = ref.watch(biometricKindProvider).value ?? BiometricKind.none;
    final enabled = ref.watch(biometricEnabledProvider).value ?? false;
    final label = kind == BiometricKind.face ? 'Unlock with Face ID' : 'Unlock with fingerprint';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(VSpace.page, 0, VSpace.page, VSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: t.headlineSmall),
            const SizedBox(height: VSpace.md),
            if (kind == BiometricKind.none)
              Text('Biometric unlock isn’t set up on this device.', style: t.bodyMedium)
            else
              SwitchListTile(
                key: const Key('biometric-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                subtitle: const Text('Your PIN always works too.'),
                value: enabled,
                onChanged: (on) async {
                  // Turning it on needs a successful biometric check first.
                  if (on && !await ref.read(biometricsProvider).authenticate('Turn on biometric unlock')) return;
                  await ref.read(biometricEnabledProvider.notifier).set(on);
                },
              ),
          ],
        ),
      ),
    );
  }
}
