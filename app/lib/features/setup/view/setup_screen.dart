import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';

import '../../../core/api/generated/export.dart' hide Mutation;
import '../../../core/api/hiwiski_failure.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/hiwiski_metrics.dart';
import '../../../core/theme/hiwiski_symbols.dart';
import '../../../core/theme/hiwiski_tokens.dart';
import '../../../core/ui/archive_files.dart';
import '../../../core/ui/auth_scaffold.dart';
import '../../../core/ui/failure_text.dart';
import '../../../core/ui/notice_bar.dart';
import '../../../core/ui/password_field.dart';
import '../../../core/ui/hiwiski_mark.dart';
import '../setup_view_model.dart';
import 'setup_keys.dart';

/// The setup wizard: **exactly once, for the first person.**
///
/// It starts with the setup code and two ways on: **start fresh** —
/// five steps with progress, the backup password among them — or **restore from a
/// backup**, for a new machine after the old one is gone. Afterwards
/// `setup.completed` is set and the wizard can never be reached again — the server
/// rejects a second run, not just the UI.
///
/// **Every field carries its own `Key`.** All steps build into the same spot of the
/// widget tree; without keys Flutter reuses the `TextField` element and only
/// attaches a different controller. Whatever is typed in the frame in between then
/// lands in the previous step's controller — on the first run that is why the
/// username ended up in the database as the family name.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

/// Which way the wizard goes after the setup code.
enum _Way { choose, fresh, restore }

class _SetupScreenState extends ConsumerState<SetupScreen> {
  static const _freshSteps = 5;
  static const _restoreSteps = 4;

  /// The fresh way's steps.
  static const _family = 0;
  static const _admin = 1;
  static const _backup = 2;
  static const _groupsAt = 3;

  /// The restore way's steps.
  static const _file = 0;
  static const _unlock = 1;
  static const _preview = 2;

  _Way _way = .choose;
  int _step = 0;
  bool _busy = false;
  String? _error;

  final _setupCode = TextEditingController();
  final _familyName = TextEditingController();
  final _timezone = TextEditingController();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordRepeat = TextEditingController();
  final _backupPassword = TextEditingController();
  final _backupPasswordRepeat = TextEditingController();
  final _restorePassword = TextEditingController();

  /// The archive on the server, and what its manifest says.
  ({String name, String id})? _uploaded;
  BackupPreview? _previewed;
  String? _backupError;
  String? _restorePasswordError;

  /// Suggested in the language of the UI — filled in [didChangeDependencies], the
  /// first place the localizations are available.
  final _groups = <TextEditingController>[];
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _password.addListener(_clearPasswordError);
    _passwordRepeat.addListener(_clearPasswordError);
    _backupPassword.addListener(_clearPasswordError);
    _backupPasswordRepeat.addListener(_clearPasswordError);
    _prefillTimezone();
    // Used without a server before: the administrator is that member.
    _displayName.text = ref.read(setupViewModelProvider).localName ?? '';
  }

  /// A corrected repeat clears "Passwords do not match" — it stood until the next try.
  void _clearPasswordError() {
    if ((_passwordError != null || _backupError != null) && mounted) {
      setState(() {
        _passwordError = null;
        _backupError = null;
      });
    }
  }

  /// Prefilled from the device: the home time zone is almost always the first
  /// person's. Where the device cannot say, the field stays empty to be typed.
  Future<void> _prefillTimezone() async {
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      if (mounted && _timezone.text.isEmpty) _timezone.text = zone.identifier;
    } on Object catch (error) {
      // Left to the person setting up.
      debugPrint('hiwiski: device time zone unavailable: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_groups.isEmpty) {
      final l = L.of(context);
      _groups.addAll([
        TextEditingController(text: l.setupGroupEveryone),
        TextEditingController(text: l.setupGroupParents),
      ]);
    }
  }

  @override
  void dispose() {
    _familyName.dispose();
    _setupCode.dispose();
    _timezone.dispose();
    _displayName.dispose();
    _username.dispose();
    _password
      ..removeListener(_clearPasswordError)
      ..dispose();
    _passwordRepeat
      ..removeListener(_clearPasswordError)
      ..dispose();
    _backupPassword
      ..removeListener(_clearPasswordError)
      ..dispose();
    _backupPasswordRepeat
      ..removeListener(_clearPasswordError)
      ..dispose();
    _restorePassword.dispose();
    for (final controller in _groups) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _steps => _way == .restore ? _restoreSteps : _freshSteps;

  bool get _canContinue => switch ((_way, _step)) {
    (.fresh, _family) =>
      _familyName.text.trim().isNotEmpty && _timezone.text.trim().isNotEmpty,
    (.fresh, _admin) =>
      _displayName.text.trim().isNotEmpty &&
          _username.text.trim().isNotEmpty &&
          _password.text.length >= _minimumPassword,
    (.fresh, _backup) => _backupPassword.text.length >= _minimumPassword,
    (.fresh, _groupsAt) => _groups.any(
      (controller) => controller.text.trim().isNotEmpty,
    ),
    (.restore, _file) => _uploaded != null,
    (.restore, _unlock) => _restorePassword.text.isNotEmpty,
    _ => true,
  };

  static const _minimumPassword = 8;

  /// Back to the setup code — where a wrong one is corrected.
  void _backToCode(String error) => setState(() {
    _error = error;
    _way = .choose;
    _step = 0;
  });

  void _continue() {
    setState(() => _error = null);
    switch ((_way, _step)) {
      case (.fresh, final step) when step == _freshSteps - 1:
        unawaited(_finish());
      case (.fresh, _backup) when !_backupPasswordValid():
        return;
      case (.restore, _unlock):
        unawaited(_inspect());
      case (.restore, _preview):
        unawaited(_restoreArchive());
      case _:
        setState(() => _step++);
    }
  }

  /// Typed twice, and not the administrator's.
  bool _backupPasswordValid() {
    final l = L.of(context);
    final error = switch (_backupPassword.text) {
      final typed when typed != _backupPasswordRepeat.text =>
        l.passwordMismatch,
      final typed when typed == _password.text => l.setupBackupSameAsAdmin,
      _ => null,
    };
    setState(() => _backupError = error);
    return error == null;
  }

  Future<void> _pickAndUpload() async {
    final picked = await pickArchive();
    if (picked == null || !mounted) return;
    final code = _setupCode.text.trim();
    try {
      final upload = await setupUploadMutation.run(
        ref,
        (tsx) => tsx
            .get(setupViewModelProvider.notifier)
            .upload(code, picked.bytes, picked.length),
      );
      if (mounted) {
        setState(() {
          _uploaded = (name: picked.name, id: upload.id);
          _previewed = null;
        });
      }
    } on Object catch (error) {
      _fail(error);
    }
  }

  Future<void> _inspect() async {
    final uploaded = _uploaded;
    if (uploaded == null) return;
    final code = _setupCode.text.trim();
    final password = _restorePassword.text;
    try {
      final preview = await setupInspectMutation.run(
        ref,
        (tsx) => tsx
            .get(setupViewModelProvider.notifier)
            .inspect(code, uploaded.id, password),
      );
      if (mounted) {
        setState(() {
          _previewed = preview;
          _restorePasswordError = null;
          _step = _preview;
        });
      }
    } on Object catch (error) {
      final failure = HiwiskiFailure.from(error);
      if (!mounted) return;
      // A wrong one stays on this step.
      if (failure.code == FailureCodes.backupPasswordWrong) {
        setState(() => _restorePasswordError = failureText(context, failure));
      } else {
        _fail(failure);
      }
    }
  }

  Future<void> _restoreArchive() async {
    final uploaded = _uploaded;
    if (uploaded == null) return;
    final code = _setupCode.text.trim();
    final password = _restorePassword.text;
    setState(() => _step = _restoreSteps - 1);
    try {
      // The session goes on to the sign-in once it is done.
      await setupRestoreMutation.run(
        ref,
        (tsx) => tsx
            .get(setupViewModelProvider.notifier)
            .restore(code, uploaded.id, password),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _step = _preview);
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (!mounted) return;
    final failure = HiwiskiFailure.from(error);
    final text = failureText(context, failure);
    if (failure.code == FailureCodes.setupCodeInvalid) {
      _backToCode(text);
    } else if (failure.code == FailureCodes.backupUploadNotFound) {
      // Gone an hour after the upload: once more from the file.
      setState(() {
        _error = text;
        _uploaded = null;
        _step = _file;
      });
    } else {
      setState(() => _error = text);
    }
  }

  Future<void> _finish() async {
    final l = L.of(context);
    if (_password.text != _passwordRepeat.text) {
      setState(() {
        _step = _admin;
        _passwordError = l.passwordMismatch;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // The catalog starts in the wizard's language.
    final language = Localizations.localeOf(context).languageCode;
    try {
      await ref
          .read(setupViewModelProvider.notifier)
          .setUp(
            (device) => SetupRequest(
              setupCode: _setupCode.text.trim(),
              familyName: _familyName.text.trim(),
              timezone: _timezone.text.trim(),
              admin: SetupAdmin(
                displayName: _displayName.text.trim(),
                username: _username.text.trim(),
                password: _password.text,
              ),
              groups: [
                for (final controller in _groups)
                  if (controller.text.trim().isNotEmpty) controller.text.trim(),
              ],
              device: device,
              language: language,
              backupPassword: _backupPassword.text,
            ),
          );
    } on Object catch (error) {
      // Not only the server's failures: the device info can fail too, and then the
      // spinner stopped without a word.
      if (mounted) {
        final failure = HiwiskiFailure.from(error);
        setState(() {
          _error = failureText(context, failure);
          // The code comes before both ways: back there, so it can be corrected.
          if (failure.code == FailureCodes.setupCodeInvalid) {
            _way = .choose;
            _step = 0;
          }
          if (failure.code == FailureCodes.setupBackupPasswordSame) {
            _step = _backup;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(setupViewModelProvider);
    final fromLocal = state.localName != null;
    final busy =
        _busy ||
        ref.watch(setupUploadMutation).isPending ||
        ref.watch(setupInspectMutation).isPending ||
        ref.watch(setupRestoreMutation).isPending;

    return AuthScaffold(
      loading: busy,
      notice: switch ((_error, fromLocal)) {
        (final error?, _) => NoticeBar.error(context, text: error),
        (null, true) => NoticeBar(
          icon: HiwiskiSymbols.cloudUpload,
          text: l.localMoveNotice,
        ),
        _ => null,
      },
      onBack: switch ((_way, _step, fromLocal)) {
        (.choose, _, true) =>
          () => ref.read(setupViewModelProvider.notifier).backToLocal(),
        (.choose, _, false) => null,
        // Restoring: there is no way back from it.
        (.restore, final step, _) when step == _restoreSteps - 1 => null,
        (_, 0, _) => () => setState(() {
          _error = null;
          _way = .choose;
        }),
        _ => () => setState(() => _step--),
      },
      children: _way == .choose
          ? _chooseStep(l, busy)
          : [
              Text(
                l.setupStep(_step + 1, _steps),
                style: context.texts.bodySmall?.copyWith(
                  color: context.scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: HiwiskiMetrics.space6),
              ClipRRect(
                borderRadius: const .all(.circular(HiwiskiMetrics.radiusBar)),
                child: LinearProgressIndicator(value: (_step + 1) / _steps),
              ),
              const SizedBox(height: HiwiskiMetrics.space24),
              ...switch ((_way, _step)) {
                (.fresh, _family) => _familyStep(l),
                (.fresh, _admin) => _adminStep(l),
                (.fresh, _backup) => _backupStep(l),
                (.fresh, _groupsAt) => _groupsStep(l),
                (.fresh, _) => _doneStep(l),
                (.restore, _file) => _fileStep(l, state.uploaded, busy),
                (.restore, _unlock) => _unlockStep(l),
                (.restore, _preview) => _previewStep(l),
                _ => _restoringStep(l),
              },
              const SizedBox(height: HiwiskiMetrics.space24),
              if (!(_way == .restore && _step == _restoreSteps - 1))
                // "Continue" follows every field it depends on, however it
                // changes: the password field said nothing, and the button
                // stayed disabled after a valid password; the zone filled in
                // from the device did not rebuild either.
                ListenableBuilder(
                  listenable: Listenable.merge([
                    _familyName,
                    _timezone,
                    _displayName,
                    _username,
                    _password,
                    _backupPassword,
                    _restorePassword,
                    ..._groups,
                  ]),
                  builder: (context, _) => FilledButton(
                    onPressed: busy || !_canContinue ? null : _continue,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        HiwiskiMetrics.buttonHeightLarge,
                      ),
                    ),
                    child: Text(switch ((_way, _step)) {
                      (.fresh, final step) when step == _freshSteps - 1 =>
                        l.setupStart,
                      (.restore, _preview) => l.setupRestoreStart,
                      _ => l.actionContinue,
                    }),
                  ),
                ),
            ],
    );
  }

  /// The setup code, then the two ways on.
  List<Widget> _chooseStep(L l, bool busy) => [
    const HiwiskiMark(),
    const SizedBox(height: HiwiskiMetrics.space14),
    Text(l.setupTitle, style: context.texts.headlineLarge),
    const SizedBox(height: HiwiskiMetrics.space20),
    // The code from the server's log: without it whoever reached a fresh server first
    // became its administrator.
    TextField(
      key: SetupKeys.setupCode,
      controller: _setupCode,
      autofocus: true,
      autocorrect: false,
      textCapitalization: .characters,
      style: context.tokens.text.monoSmall,
      decoration: InputDecoration(
        labelText: l.setupCode,
        helperText: l.setupCodeHint,
        helperMaxLines: 4,
      ),
    ),
    const SizedBox(height: HiwiskiMetrics.space20),
    Text(
      l.setupChoiceLead,
      style: context.texts.bodySmall?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: HiwiskiMetrics.space16),
    ListenableBuilder(
      listenable: _setupCode,
      builder: (context, _) {
        final ready = !busy && _setupCode.text.trim().isNotEmpty;
        void go(_Way way) => setState(() {
          _error = null;
          _way = way;
          _step = 0;
        });
        return Column(
          crossAxisAlignment: .stretch,
          spacing: HiwiskiMetrics.space12,
          children: [
            FilledButton(
              key: SetupKeys.startFresh,
              onPressed: ready ? () => go(.fresh) : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  HiwiskiMetrics.buttonHeightLarge,
                ),
              ),
              child: Text(l.setupChoiceFresh),
            ),
            OutlinedButton.icon(
              key: SetupKeys.restoreBackup,
              onPressed: ready ? () => go(.restore) : null,
              icon: const Icon(HiwiskiSymbols.backup),
              label: Text(l.setupChoiceRestore),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  HiwiskiMetrics.buttonHeightLarge,
                ),
              ),
            ),
          ],
        );
      },
    ),
  ];

  List<Widget> _familyStep(L l) => [
    Text(l.setupFamilyTitle, style: context.texts.titleLarge),
    const SizedBox(height: HiwiskiMetrics.space16),
    TextField(
      key: SetupKeys.familyName,
      controller: _familyName,
      autofocus: true,
      textInputAction: .next,
      decoration: InputDecoration(labelText: l.setupFamilyName),
    ),
    const SizedBox(height: HiwiskiMetrics.space20),
    TextField(
      key: SetupKeys.timezone,
      controller: _timezone,
      autocorrect: false,
      decoration: InputDecoration(labelText: l.setupTimezone),
    ),
  ];

  List<Widget> _adminStep(L l) => [
    Text(l.setupAdminTitle, style: context.texts.titleLarge),
    const SizedBox(height: HiwiskiMetrics.space6),
    Text(
      l.setupAdminLead,
      style: context.texts.bodySmall?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: HiwiskiMetrics.space16),
    TextField(
      key: SetupKeys.displayName,
      controller: _displayName,
      autofocus: true,
      textInputAction: .next,
      decoration: InputDecoration(labelText: l.setupDisplayName),
    ),
    const SizedBox(height: HiwiskiMetrics.space20),
    TextField(
      key: SetupKeys.username,
      controller: _username,
      autocorrect: false,
      textInputAction: .next,
      decoration: InputDecoration(labelText: l.setupUsername),
    ),
    const SizedBox(height: HiwiskiMetrics.space20),
    PasswordField(
      key: SetupKeys.password,
      controller: _password,
      label: l.setupPassword,
      textInputAction: .next,
    ),
    const SizedBox(height: HiwiskiMetrics.space20),
    PasswordField(
      key: SetupKeys.passwordRepeat,
      controller: _passwordRepeat,
      label: l.setupPasswordRepeat,
      errorText: _passwordError,
    ),
  ];

  /// Every backup is locked with it — and nobody can reset it.
  List<Widget> _backupStep(L l) => [
    Text(l.setupBackupTitle, style: context.texts.titleLarge),
    const SizedBox(height: HiwiskiMetrics.space6),
    Text(l.setupBackupLead, style: context.texts.bodyMedium),
    const SizedBox(height: HiwiskiMetrics.space8),
    Text(
      l.setupBackupNotAdmin,
      style: context.texts.bodySmall?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: HiwiskiMetrics.space16),
    PasswordField(
      key: SetupKeys.backupPassword,
      controller: _backupPassword,
      label: l.setupBackupPassword,
      autofocus: true,
      textInputAction: .next,
    ),
    const SizedBox(height: HiwiskiMetrics.space20),
    PasswordField(
      key: SetupKeys.backupPasswordRepeat,
      controller: _backupPasswordRepeat,
      label: l.setupBackupPasswordRepeat,
      errorText: _backupError,
    ),
  ];

  List<Widget> _groupsStep(L l) => [
    Text(l.setupGroupsTitle, style: context.texts.titleLarge),
    const SizedBox(height: HiwiskiMetrics.space6),
    Text(
      l.setupGroupsLead,
      style: context.texts.bodySmall?.copyWith(
        color: context.scheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: HiwiskiMetrics.space16),
    for (var i = 0; i < _groups.length; i++)
      Padding(
        // Keyed by the controller, not the position: after a removal the fields
        // below kept their places' elements with the next group's controller, and
        // focus and typing moved to the wrong group.
        key: ObjectKey(_groups[i]),
        padding: const .only(bottom: HiwiskiMetrics.space12),
        child: Row(
          children: [
            Expanded(
              // No positional key here either: a changed key rebuilds the field,
              // and its focus went with it.
              child: TextField(
                controller: _groups[i],
                decoration: InputDecoration(labelText: '${i + 1}.'),
              ),
            ),
            if (_groups.length > 1)
              IconButton(
                icon: const Icon(HiwiskiSymbols.close),
                onPressed: () {
                  final removed = _groups[i];
                  setState(() => _groups.removeAt(i));
                  // Once its field is gone — disposed right away, it was still
                  // attached to the field being rebuilt.
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => removed.dispose(),
                  );
                },
                tooltip: l.actionDelete,
              ),
          ],
        ),
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _groups.add(TextEditingController())),
        icon: const Icon(HiwiskiSymbols.add),
        label: Text(l.setupGroupAdd),
      ),
    ),
  ];

  List<Widget> _doneStep(L l) => [
    Icon(
      HiwiskiSymbols.checkCircle,
      fill: 1,
      size: HiwiskiMetrics.icon48,
      color: context.scheme.primary,
    ),
    const SizedBox(height: HiwiskiMetrics.space14),
    Text(l.setupDoneTitle, style: context.texts.titleLarge),
    const SizedBox(height: HiwiskiMetrics.space8),
    Text(l.setupDoneLead, style: context.texts.bodyMedium),
    const SizedBox(height: HiwiskiMetrics.space12),
    // Where the backups go — and that they must leave the machine.
    Text(l.setupDoneBackups, style: context.texts.bodyMedium),
  ];

  // --- Restoring from a backup ------------------------------------------------

  List<Widget> _fileStep(L l, double? uploaded, bool busy) => [
    Text(l.setupRestoreFileTitle, style: context.texts.titleLarge),
    const SizedBox(height: HiwiskiMetrics.space6),
    Text(l.setupRestoreFileLead, style: context.texts.bodyMedium),
    const SizedBox(height: HiwiskiMetrics.space16),
    OutlinedButton.icon(
      onPressed: busy ? null : () => unawaited(_pickAndUpload()),
      icon: const Icon(HiwiskiSymbols.upload),
      label: Text(l.setupRestorePick),
    ),
    const SizedBox(height: HiwiskiMetrics.space12),
    if (uploaded != null) ...[
      LinearProgressIndicator(value: uploaded),
      const SizedBox(height: HiwiskiMetrics.space6),
      Text(l.setupRestoreUploading((uploaded * _percent).round())),
    ] else if (_uploaded case final done?)
      Text(l.setupRestoreUploaded(done.name)),
  ];

  static const _percent = 100;

  List<Widget> _unlockStep(L l) => [
    Text(l.setupBackupTitle, style: context.texts.titleLarge),
    const SizedBox(height: HiwiskiMetrics.space6),
    Text(l.setupRestorePasswordLead, style: context.texts.bodyMedium),
    const SizedBox(height: HiwiskiMetrics.space16),
    PasswordField(
      key: SetupKeys.restorePassword,
      controller: _restorePassword,
      label: l.setupBackupPassword,
      autofocus: true,
      errorText: _restorePasswordError,
      onSubmitted: _restorePassword.text.isEmpty ? null : _continue,
    ),
  ];

  List<Widget> _previewStep(L l) {
    final preview = _previewed;
    if (preview == null) return const [];
    final when = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(preview.createdAt.toLocal());
    return [
      Text(l.setupRestorePreviewTitle, style: context.texts.titleLarge),
      const SizedBox(height: HiwiskiMetrics.space12),
      Text(
        [
          l.backupPreviewWhen(when),
          if (preview.familyName case final name?) l.backupPreviewFamily(name),
          l.backupPreviewVersion(preview.serverVersion),
          l.unitMegabytes(
            (preview.bytes / _bytesPerMegabyte).toStringAsFixed(1),
          ),
          l.backupPreviewMembers(preview.members),
        ].join('\n'),
        style: context.texts.bodyMedium,
      ),
      const SizedBox(height: HiwiskiMetrics.space16),
      Text(
        l.setupRestoreLead,
        style: context.texts.bodySmall?.copyWith(
          color: context.scheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  static const _bytesPerMegabyte = 1024 * 1024;

  List<Widget> _restoringStep(L l) => [
    const LinearProgressIndicator(),
    const SizedBox(height: HiwiskiMetrics.space12),
    Text(l.setupRestoreRunning, style: context.texts.bodyMedium),
  ];
}
