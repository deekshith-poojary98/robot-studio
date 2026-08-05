import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../environment/python_install_guidance.dart';

/// User-facing failure dialog: what happened, how to fix it, raw detail hidden
/// behind "Show details" so nobody reads a stack trace by accident.
Future<void> showFriendlyErrorDialog({
  required BuildContext context,
  required String title,
  required Object error,
  String? recovery,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final details = error.toString();
  final copy = resolveFriendlyError(details);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _FriendlyErrorDialog(
      title: title,
      summary: copy.summary,
      recovery: recovery ?? copy.recovery,
      details: details,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

/// Warning dialog that can proceed anyway. Returns `true` if the user chose
/// [continueLabel], `false` if they closed / dismissed.
Future<bool> showContinueAnywayDialog({
  required BuildContext context,
  required String title,
  required Object error,
  String? summary,
  String? recovery,
  String continueLabel = 'Continue anyways',
}) async {
  final details = error.toString();
  final copy = resolveFriendlyError(details);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _FriendlyErrorDialog(
      title: title,
      summary: summary ?? copy.summary,
      recovery: recovery ?? copy.recovery,
      details: details,
      warning: true,
      continueLabel: continueLabel,
    ),
  );
  return result ?? false;
}

class FriendlyErrorCopy {
  const FriendlyErrorCopy({required this.summary, required this.recovery});

  final String summary;
  final String recovery;
}

/// Turns transport/exception noise into a plain summary + next step.
///
/// Prefer specific patterns; otherwise surface a cleaned backend detail so
/// users never only see “That action did not finish.” for known validation
/// messages like `Path does not exist` or `Not a Git repository`.
FriendlyErrorCopy resolveFriendlyError(String raw) {
  final cleaned = cleanErrorMessage(raw);
  final text = cleaned.toLowerCase();
  final rawLower = raw.toLowerCase();

  // Raw exception / Future / traceback noise — check the original payload first
  // so cleaning "KeyError: 'x'" into "'x'" cannot leak as the summary.
  if (_any(rawLower, const [
        'traceback',
        'stacktrace',
        'future not completed',
        'future already completed',
        'bad state:',
        'keyerror',
        'typeerror',
        'attributeerror',
        'valueerror',
        'runtimeerror',
        'assertionerror',
        'null check operator',
        'nosuchmethoderror',
      ]) &&
      !_any(rawLower, const [
        'timeout',
        'timed out',
        'robot framework',
        'path does not exist',
        'permission denied',
      ])) {
    return const FriendlyErrorCopy(
      summary: 'Something went wrong while handling that action.',
      recovery:
          'Try again. If it keeps failing, check the details below or restart '
          'Robot Studio.',
    );
  }

  // Connectivity
  if (_any(text, const [
    'connection refused',
    'failed host lookup',
    'socketexception',
    'network is unreachable',
    'clientexception',
  ])) {
    return const FriendlyErrorCopy(
      summary: 'Robot Studio could not reach its backend service.',
      recovery: 'Make sure the backend is running, then try again.',
    );
  }

  // Timeouts
  if (_any(text, const ['timeout', 'timed out'])) {
    return const FriendlyErrorCopy(
      summary: 'That is taking longer than expected.',
      recovery:
          'Still working in the background — try again in a moment, or wait '
          'for a larger project to finish indexing.',
    );
  }

  // Permissions / disk
  if (_any(text, const [
    'permission denied',
    'errno 13',
    'operation not permitted',
  ])) {
    return const FriendlyErrorCopy(
      summary: 'Robot Studio is not allowed to use that file or folder.',
      recovery: 'Pick a different location, or fix the folder permissions.',
    );
  }
  if (_any(text, const ['no space left', 'errno 28'])) {
    return const FriendlyErrorCopy(
      summary: 'The disk is full, so the change could not be saved.',
      recovery: 'Free up disk space, then retry.',
    );
  }

  // Name collisions
  if (_any(text, const ['already exists', 'errno 17'])) {
    return const FriendlyErrorCopy(
      summary: 'Something with that name already exists.',
      recovery: 'Choose another name, or open the existing item instead.',
    );
  }

  // Deleted workspace/project root (before generic "not found")
  if (text.contains('no longer on disk')) {
    return const FriendlyErrorCopy(
      summary:
          'The folder for this workspace was deleted outside Robot Studio.',
      recovery:
          'Nothing was saved, so the deleted folder is not recreated. Restore '
          'the folder from Trash, or close this workspace and open another.',
    );
  }

  // Pip install during Create Environment — must run before "no such file"
  // path matchers (getcwd failures include Errno 2).
  if (text.contains('failed to install robot framework') ||
      (text.contains('failed to install') && text.contains('robotframework'))) {
    final badCwd = _any(text, const [
      'getcwd',
      'no such file or directory',
      'errno 2',
    ]);
    return FriendlyErrorCopy(
      summary: 'Could not install Robot Framework into the new environment.',
      recovery: badCwd
          ? 'Pip could not read the working directory. Try Create Environment '
                'again, or restart Robot Studio and retry.'
          : 'Check your network connection and that the selected Python can '
                'use pip, then try Create Environment again.',
    );
  }

  // Missing paths / projects (before generic "not found")
  if (_any(text, const [
        'path does not exist',
        'file not found',
        'path not found',
        'no such file',
        'does not exist',
        'errno 2',
      ]) ||
      (text.contains('project not found') || text.contains('run not found'))) {
    return const FriendlyErrorCopy(
      summary: 'Robot Studio could not find that project or folder.',
      recovery:
          'It may have been deleted, moved, or renamed. Remove it from '
          'Recents if it is gone, or open the folder from its new location.',
    );
  }

  // Project open warnings
  if (text.contains('does not look like a robot framework project')) {
    return const FriendlyErrorCopy(
      summary: 'This folder does not look like a Robot Framework project.',
      recovery:
          'You can still open it. Robot Studio will treat the folder as a project.',
    );
  }

  // Virtualenv / ensurepip (before generic env / Robot Framework matchers)
  if (_any(text, const [
    'ensurepip',
    'python3-venv',
    'no module named venv',
    'failed to create virtual environment',
    'unable to create virtual environment',
  ])) {
    return FriendlyErrorCopy(
      summary: 'Could not create a Python virtual environment.',
      recovery: _venvRecoveryHint(),
    );
  }

  // Context required
  if (_any(text, const [
    'open a workspace',
    'open a project',
    'before accessing files',
    'before managing projects',
    'before running tests',
    'before using git',
    'before indexing',
    'before using language',
    'before using test explorer',
  ])) {
    return const FriendlyErrorCopy(
      summary: 'Open a project first to continue.',
      recovery: 'Use File → Open Project…, then try this action again.',
    );
  }

  // Path / name validation
  if (_any(text, const [
    'outside the active workspace',
    'cannot move a folder into itself',
    'cannot delete the workspace root',
    'destination must be a folder',
  ])) {
    return FriendlyErrorCopy(
      summary: cleaned,
      recovery: 'Stay inside the open project folder and try again.',
    );
  }
  if (_any(text, const [
    'name cannot',
    'name is not allowed',
    'invalid characters',
    'reserved name',
    'name is required',
    'project name is required',
  ])) {
    return FriendlyErrorCopy(
      summary: cleaned,
      recovery: 'Pick a different name and try again.',
    );
  }
  if (text.contains('could not complete case-only rename')) {
    return const FriendlyErrorCopy(
      summary: 'That case-only rename could not be completed.',
      recovery: 'Try renaming again, or restart Robot Studio and retry.',
    );
  }

  // Git
  if (_any(text, const [
    'not a git repository',
    'commit message is required',
    'git command',
    'failed to start git',
    'commit not found',
  ])) {
    if (text.contains('not a git repository')) {
      return const FriendlyErrorCopy(
        summary: 'This folder is not a Git repository.',
        recovery: 'Initialize Git from Source Control, then try again.',
      );
    }
    if (text.contains('commit message is required')) {
      return const FriendlyErrorCopy(
        summary: 'A commit message is required.',
        recovery: 'Enter a message in the Source Control commit box.',
      );
    }
    return FriendlyErrorCopy(
      summary: cleaned,
      recovery: 'Check Source Control and try the Git action again.',
    );
  }

  // Execution / reports
  if (_any(text, const [
    'no active execution',
    'no running execution',
    'no previous run',
    'no failed tests',
    'select at least one test',
    'not available for this run',
  ])) {
    return FriendlyErrorCopy(
      summary: cleaned,
      recovery: 'Run tests from the Tests view, then try again.',
    );
  }

  // Environments / Robot / packages
  if (_any(text, const [
    'no python interpreter',
    'activate an environment with robot',
    'robot framework',
    'invalid package version',
    'package name is required',
    'protected package',
    'pip ',
    'getcwd',
  ])) {
    if (text.contains('no python interpreter')) {
      return FriendlyErrorCopy(
        summary: PythonInstallGuidance.summary,
        recovery: PythonInstallGuidance.shortRecovery,
      );
    }
    if (text.contains('getcwd') &&
        (text.contains('pip') || text.contains('robot'))) {
      return const FriendlyErrorCopy(
        summary: 'Could not install packages into the environment.',
        recovery:
            'Pip could not read the working directory. Restart Robot Studio '
            'and try again.',
      );
    }
    if (text.contains('activate an environment with robot') ||
        text.contains('robot framework is not installed') ||
        text.contains('could not verify robot framework') ||
        (text.contains('robot framework') &&
            (text.contains('not installed') ||
                text.contains('not available') ||
                text.contains('missing')))) {
      return const FriendlyErrorCopy(
        summary: 'Robot Framework is not installed in the active environment.',
        recovery:
            'Install Robot Framework into this environment, or choose another '
            'environment that already has it.',
      );
    }
    if (text.contains('robot framework')) {
      return const FriendlyErrorCopy(
        summary: 'Robot Framework is not available in the active environment.',
        recovery:
            'Activate an environment with Robot Framework installed, or install '
            'it from Packages.',
      );
    }
    if (text.contains('aborted') || text.contains('failed to start')) {
      return const FriendlyErrorCopy(
        summary: 'The test run never started.',
        recovery:
            'Fix the environment or suite path, then press F5 to try again. '
            'Aborted launches are not kept in history.',
      );
    }
    return FriendlyErrorCopy(
      summary: cleaned,
      recovery: 'Check the active environment in the toolbar, then try again.',
    );
  }
  // Broad env fallback (after more specific checks).
  if (text.contains('environment') &&
      !_any(text, const ['does not look like', 'path does not exist'])) {
    return FriendlyErrorCopy(
      summary: cleaned.isNotEmpty && _looksHumanReadable(cleaned)
          ? cleaned
          : 'The Python environment could not complete this request.',
      recovery: 'Check the active environment in the toolbar, then try again.',
    );
  }

  // HTTP / transport noise with no useful detail
  if (RegExp(r'^request failed \(\d+\)$').hasMatch(text)) {
    return const FriendlyErrorCopy(
      summary: 'The backend rejected that request.',
      recovery: 'Try again. If it keeps failing, check the details below.',
    );
  }
  if (_any(text, const [
    'http 500',
    'status code 500',
    'internal server error',
    'request failed (500)',
    'request failed (502)',
    'request failed (503)',
  ])) {
    return const FriendlyErrorCopy(
      summary: 'The backend hit an unexpected error.',
      recovery:
          'Try again. If it keeps failing, restart the backend and check the '
          'details below.',
    );
  }
  if (text.contains('unexpected response from backend')) {
    return const FriendlyErrorCopy(
      summary: 'The backend returned an unexpected response.',
      recovery: 'Restart the backend and try again.',
    );
  }

  // Raw exception leftovers after cleaning (e.g. "'project_id'" from KeyError).
  if (_any(text, const [
    'traceback',
    'stacktrace',
    'future not completed',
    'future already completed',
    'bad state:',
  ])) {
    return const FriendlyErrorCopy(
      summary: 'Something went wrong while handling that action.',
      recovery:
          'Try again. If it keeps failing, check the details below or restart '
          'Robot Studio.',
    );
  }

  // Prefer a cleaned human detail over the generic line.
  if (_looksHumanReadable(cleaned) && !_looksLikeRawException(cleaned)) {
    return FriendlyErrorCopy(
      summary: cleaned,
      recovery: 'Try again. If it keeps failing, check the details below.',
    );
  }

  return const FriendlyErrorCopy(
    summary: 'That action did not finish.',
    recovery: 'Try again. If it keeps failing, check the details below.',
  );
}

/// Turns transport/exception noise into one plain sentence.
String friendlyErrorSummary(String raw) => resolveFriendlyError(raw).summary;

/// Suggests the next step for the same error families.
String friendlyErrorRecovery(String raw) => resolveFriendlyError(raw).recovery;

/// Strip exception-type prefixes and stack noise; keep the first useful line.
@visibleForTesting
String cleanErrorMessage(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return text;

  // Prefer the first non-stack line.
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .where((line) => !line.startsWith('#'))
      .where((line) => !RegExp(r'^at\s').hasMatch(line))
      .toList();
  if (lines.isNotEmpty) {
    text = lines.first;
  }

  // Exception: message / GatewayException: message / Error: message
  text = text.replaceFirst(
    RegExp(
      r'^(?:instance of\s+[\w.]+|[\w.]+(?:error|exception)|gatewayexception)\s*:\s*',
      caseSensitive: false,
    ),
    '',
  );

  // Flutter/Dart often wraps as "Exception: …"
  text = text.replaceFirst(RegExp(r'^exception:\s*', caseSensitive: false), '');

  // Drop surrounding quotes when the whole message is quoted.
  if ((text.startsWith("'") && text.endsWith("'")) ||
      (text.startsWith('"') && text.endsWith('"'))) {
    text = text.substring(1, text.length - 1);
  }

  return text.trim();
}

bool _looksHumanReadable(String text) {
  if (text.isEmpty || text.length > 220) return false;
  final lower = text.toLowerCase();
  if (lower.contains('stacktrace') || lower.contains('stack overflow')) {
    return false;
  }
  // Reject pure type names / status codes without prose.
  if (RegExp(r'^[A-Za-z_.]+Exception$').hasMatch(text)) return false;
  if (RegExp(r'^HTTP\s*\d{3}$').hasMatch(text)) return false;
  // Prefer sentences / phrases with spaces or punctuation.
  return text.contains(' ') || text.contains("'") || text.contains('/');
}

bool _looksLikeRawException(String text) {
  final lower = text.toLowerCase();
  if (_any(lower, const [
    'traceback',
    'future not completed',
    'keyerror',
    'typeerror',
    'attributeerror',
    '#0 ',
    'package:',
  ])) {
    return true;
  }
  // "KeyError: 'foo'" / "TimeoutException after …" without helpful prose.
  if (RegExp(r'^[A-Za-z_.]*(Error|Exception)\b').hasMatch(text) &&
      !text.contains(' ')) {
    return true;
  }
  return false;
}

bool _any(String text, List<String> needles) => needles.any(text.contains);

String _venvRecoveryHint() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    return 'Install a full Python 3 build (brew install python, or python.org), '
        'then create the environment again.';
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    return 'Reinstall Python from python.org with pip enabled, then create '
        'the environment again.';
  }
  return 'Install the venv package for your Python '
      '(e.g. sudo apt install python3-venv), then create the environment again.';
}

class _FriendlyErrorDialog extends StatefulWidget {
  const _FriendlyErrorDialog({
    required this.title,
    required this.summary,
    required this.recovery,
    required this.details,
    this.actionLabel,
    this.onAction,
    this.warning = false,
    this.continueLabel,
  });

  final String title;
  final String summary;
  final String recovery;
  final String details;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool warning;
  final String? continueLabel;

  @override
  State<_FriendlyErrorDialog> createState() => _FriendlyErrorDialogState();
}

class _FriendlyErrorDialogState extends State<_FriendlyErrorDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.warning ? Icons.warning_amber_rounded : Icons.error_outline,
            size: 20,
            color: widget.warning
                ? context.palette.warning
                : context.palette.error,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: AppDialogWidth.form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.summary),
            const SizedBox(height: 10),
            Text(widget.recovery, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('error.show-details'),
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(
                  _showDetails ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(_showDetails ? 'Hide details' : 'Show details'),
              ),
            ),
            if (_showDetails) ...[
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: context.palette.border),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.details,
                    style: TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 11.5,
                      height: 1.4,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => unawaitedCopy(widget.details),
                  icon: const Icon(Icons.copy_all_outlined, size: 15),
                  label: const Text('Copy details'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.continueLabel != null) ...[
          TextButton(
            key: const Key('warning.close'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('warning.continue'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.continueLabel!),
          ),
        ] else ...[
          if (widget.actionLabel != null && widget.onAction != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onAction!();
              },
              child: Text(widget.actionLabel!),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ],
    );
  }
}

void unawaitedCopy(String value) {
  Clipboard.setData(ClipboardData(text: value));
}
