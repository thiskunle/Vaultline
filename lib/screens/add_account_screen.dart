import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/otp_account.dart';
import '../otp/base32.dart';
import '../otp/totp.dart';
import '../providers/vault_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/account_card.dart';

/// Add an authenticator account by typing or pasting its setup key.
/// Shows the live code as soon as the key is valid, so it can be checked
/// against the service before saving.
class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key, this.initial});

  /// Pre-filled from a scanned QR code, for review before saving.
  final OtpAccount? initial;

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> with SingleTickerProviderStateMixin {
  final _issuer = TextEditingController();
  final _name = TextEditingController();
  final _secret = TextEditingController();
  late final _tick = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  int _digits = 6;
  int _period = 30;
  OtpAlgorithm _algorithm = OtpAlgorithm.sha1;
  bool _submitted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      _issuer.text = a.issuer;
      _name.text = a.name;
      _secret.text = a.secret;
      _digits = a.digits;
      _period = a.period;
      _algorithm = a.algorithm;
    }
    for (final c in [_issuer, _name, _secret]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    for (final c in [_issuer, _name, _secret]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _keyValid => Base32.isValidSecret(_secret.text);

  String? get _issuerError => _submitted && _issuer.text.trim().isEmpty ? 'Enter the service name' : null;

  String? get _keyError {
    if (_secret.text.isEmpty) return _submitted ? 'Enter the setup key' : null;
    if (_keyValid) return null;
    return 'That doesn’t look like a setup key. It uses letters A–Z and digits 2–7.';
  }

  OtpAccount _draft() => OtpAccount(
    id: AccountsController.newId(),
    issuer: _issuer.text.trim().isEmpty ? 'New account' : _issuer.text.trim(),
    name: _name.text.trim(),
    secret: Base32.normalize(_secret.text),
    algorithm: _algorithm,
    digits: _digits,
    period: _period,
    createdAt: ref.read(clockProvider)(),
  );

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _secret.text = data!.text!.trim();
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_issuerError != null || _keyError != null || _saving) return;
    setState(() => _saving = true);
    final account = _draft();
    final added = await ref.read(accountsProvider.notifier).add(account);
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (!added) {
      messenger.showSnackBar(const SnackBar(content: Text('That account is already in your vault.')));
      return;
    }
    HapticFeedback.mediumImpact();
    context.pop();
    // Replace any earlier message rather than queueing behind it.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${account.issuer} added')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider);

    InputDecoration field(String label, {String? hint, String? error, Widget? suffix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      errorMaxLines: 2,
      suffixIcon: suffix,
      filled: true,
      fillColor: VColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: VColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: VColors.accent, width: 1.4),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: VColors.night,
        title: Text(widget.initial == null ? 'Add account' : 'Check and add'),
        leading: IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close_rounded), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.sm, VSpace.page, VSpace.xl),
          children: [
            Text(
              widget.initial == null
                  ? 'In the service’s security settings, turn on two-factor authentication and choose '
                        '“enter a setup key” (sometimes “can’t scan the QR code?”).'
                  : 'Scanned from a QR code. Check the details and that the code matches the service, then add it.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: VSpace.lg),
            TextField(
              key: const Key('field-issuer'),
              controller: _issuer,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: field('Service', hint: 'e.g. GitHub', error: _issuerError),
            ),
            const SizedBox(height: VSpace.md),
            TextField(
              key: const Key('field-name'),
              controller: _name,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: field('Account (optional)', hint: 'e.g. ada@example.com'),
            ),
            const SizedBox(height: VSpace.md),
            TextField(
              key: const Key('field-secret'),
              controller: _secret,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.2),
              decoration: field(
                'Setup key',
                hint: 'e.g. JBSW Y3DP EHPK 3PXP',
                error: _keyError,
                suffix: IconButton(tooltip: 'Paste', icon: const Icon(Icons.content_paste_rounded), onPressed: _paste),
              ),
            ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Advanced', style: t.titleSmall),
                subtitle: Text('Most services use the defaults', style: t.bodySmall?.copyWith(color: VColors.muted)),
                children: [
                  _Choice<int>(
                    label: 'Digits',
                    value: _digits,
                    options: const {6: '6', 8: '8'},
                    onChanged: (v) => setState(() => _digits = v),
                  ),
                  _Choice<int>(
                    label: 'Refresh every',
                    value: _period,
                    options: const {30: '30 s', 60: '60 s'},
                    onChanged: (v) => setState(() => _period = v),
                  ),
                  _Choice<OtpAlgorithm>(
                    label: 'Algorithm',
                    value: _algorithm,
                    options: {for (final a in OtpAlgorithm.values) a: a.label},
                    onChanged: (v) => setState(() => _algorithm = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: VSpace.md),
            AnimatedSize(
              duration: VMotion.medium,
              child: _keyValid
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PREVIEW · CHECK IT MATCHES THE SERVICE',
                          style: t.labelSmall?.copyWith(color: VColors.muted),
                        ),
                        const SizedBox(height: VSpace.sm),
                        AccountCard(
                          key: const Key('preview'),
                          account: _draft(),
                          tick: _tick,
                          now: now,
                          onCopy: (_) {},
                          onMore: () {},
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: VSpace.lg),
            FilledButton(
              key: const Key('save-account'),
              onPressed: _saving ? null : _save,
              child: const Text('Add to vault'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VSpace.md),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}
