import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/otp_account.dart';
import '../providers/vault_providers.dart';
import '../security/biometrics.dart';
import '../theme/app_theme.dart';
import '../widgets/account_card.dart';
import 'add_methods.dart';

/// Inside the vault: the authenticator codes.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  /// One shared tick keeps every card's ring and code in step.
  late final AnimationController _tick = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..repeat();

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  void _copy(OtpAccount a, String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${a.issuer} code copied')));
  }

  Future<void> _more(OtpAccount a) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy code'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              key: const Key('delete-account'),
              leading: const Icon(Icons.delete_outline_rounded, color: VColors.danger),
              title: const Text('Delete', style: TextStyle(color: VColors.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'copy') _copy(a, a.codeAt(ref.read(clockProvider)()));
    if (action == 'delete') await _confirmDelete(a);
  }

  Future<void> _confirmDelete(OtpAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VColors.surface,
        title: Text('Delete ${a.issuer}?'),
        content: const Text(
          'You won’t be able to get codes for this account here any more. '
          'Make sure you can still sign in to it another way before deleting.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: VColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(accountsProvider.notifier).remove(a.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final accounts = ref.watch(accountsProvider);
    final now = ref.watch(clockProvider);
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget enter(Widget w, int i) => reduced
        ? w
        : w.animate().fadeIn(delay: (60 * i).ms, duration: 350.ms).slideY(begin: 0.08, curve: Curves.easeOut);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.sm, VSpace.sm, 0),
              child: Row(
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.sm, VSpace.page, VSpace.md),
              child: Text('Authenticator', style: t.headlineMedium),
            ),
            Expanded(
              child: accounts.when(
                loading: () => const Center(child: CircularProgressIndicator.adaptive()),
                error: (_, _) => const _Message(
                  icon: Icons.error_outline_rounded,
                  title: 'Couldn’t read your accounts',
                  body: 'Nothing has been deleted. Restart Vaultline to try again.',
                ),
                data: (list) => list.isEmpty
                    ? _Message(
                        icon: Icons.shield_moon_outlined,
                        title: 'No accounts yet',
                        body: 'Add the setup key from a service’s 2FA settings\nto start getting codes here.',
                        action: FilledButton.icon(
                          key: const Key('add-first-account'),
                          onPressed: () => showAddMethods(context, ref),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add account'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(VSpace.md, 0, VSpace.md, 110),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => enter(
                          AccountCard(
                            account: list[i],
                            tick: _tick,
                            now: now,
                            onCopy: (code) => _copy(list[i], code),
                            onMore: () => _more(list[i]),
                          ),
                          i,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: (accounts.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              key: const Key('add-account'),
              backgroundColor: VColors.accent,
              foregroundColor: VColors.night,
              onPressed: () => showAddMethods(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add account', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VSpace.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              child: Icon(icon, size: 42, color: VColors.accent),
            ),
            const SizedBox(height: VSpace.lg),
            Text(title, style: t.titleMedium),
            const SizedBox(height: VSpace.sm),
            Text(body, style: t.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: VSpace.lg), action!],
          ],
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
