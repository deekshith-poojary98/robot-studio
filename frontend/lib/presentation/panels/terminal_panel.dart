import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/empty_state.dart';

/// Interactive shell in the bottom panel (workspace cwd when a project is open).
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, this.workingDirectory});

  final String? workingDirectory;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  final TerminalController _controller = TerminalController();

  Pty? _pty;
  StreamSubscription<List<int>>? _outputSub;
  String? _startedIn;
  String? _error;
  bool _sawOutput = false;

  static bool get _canStartShell {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureShell();
    });
  }

  @override
  void didUpdateWidget(covariant TerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workingDirectory != oldWidget.workingDirectory) {
      _restartShell();
    }
  }

  @override
  void dispose() {
    _tearDownPty();
    super.dispose();
  }

  void _tearDownPty() {
    _outputSub?.cancel();
    _outputSub = null;
    try {
      _pty?.kill();
    } catch (_) {}
    _pty = null;
    _startedIn = null;
    _sawOutput = false;
  }

  Future<void> _restartShell() async {
    _tearDownPty();
    _terminal.buffer.clear();
    _terminal.setCursor(0, 0);
    if (mounted) setState(() => _error = null);
    _ensureShell();
  }

  void _ensureShell() {
    if (!_canStartShell) return;
    final cwd = widget.workingDirectory;
    if (cwd == null || cwd.isEmpty) return;
    if (_pty != null && _startedIn == cwd) return;

    _tearDownPty();
    try {
      final rows = _terminal.viewHeight > 0 ? _terminal.viewHeight : 24;
      final cols = _terminal.viewWidth > 0 ? _terminal.viewWidth : 80;
      final pty = Pty.start(
        _shellExecutable,
        arguments: _shellArguments,
        workingDirectory: cwd,
        rows: rows,
        columns: cols,
      );
      _pty = pty;
      _startedIn = cwd;
      _outputSub = pty.output.listen((data) {
        _sawOutput = true;
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      pty.exitCode.then((code) {
        if (!mounted) return;
        _terminal.write('\r\n[process exited with code $code]\r\n');
        // A shell that dies before printing anything never really started.
        if (!_sawOutput && code != 0) {
          _terminal.write(
            'Could not start $_shellExecutable in $cwd.\r\n'
            'Check that the shell exists and the folder is readable.\r\n',
          );
        }
      });
      _terminal.onOutput = (data) {
        _pty?.write(utf8.encode(data));
      };
      _terminal.onResize = (w, h, pw, ph) {
        _pty?.resize(h, w);
      };
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    }
  }

  static String get _shellExecutable {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }

  /// Login shell so the user's profile (PATH, pyenv, nvm, …) is applied.
  static List<String> get _shellArguments =>
      Platform.isWindows ? const [] : const ['-l'];

  @override
  Widget build(BuildContext context) {
    final cwd = widget.workingDirectory;
    if (cwd == null || cwd.isEmpty) {
      return const EmptyState(
        icon: Icons.terminal,
        title: 'No project open',
        message: 'Open a project to start a terminal in its folder.',
        compact: true,
      );
    }

    if (!_canStartShell) {
      return ColoredBox(
        color: context.palette.rail,
        child: Center(
          child: Text(
            'Terminal is available on desktop builds.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
          ),
        ),
      );
    }

    if (_error != null) {
      return ColoredBox(
        color: context.palette.rail,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Could not start shell',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  color: context.palette.error,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _restartShell,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: context.palette.rail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(
                  Icons.folder_open,
                  size: 14,
                  color: context.palette.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cwd,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.textMuted,
                      fontFamily: 'Menlo',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Restart shell',
                  icon: const Icon(Icons.refresh, size: 14),
                  onPressed: _restartShell,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Kill shell',
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () {
                    _tearDownPty();
                    _terminal.write(
                      '\r\n[shell killed — click Restart to open a new session]\r\n',
                    );
                    setState(() {});
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: TerminalView(
              _terminal,
              controller: _controller,
              autofocus: false,
              backgroundOpacity: 1,
              theme: _studioTheme(context.palette),
              textStyle: const TerminalStyle(fontSize: 12, fontFamily: 'Menlo'),
              onSecondaryTapDown: (details, offset) async {
                final selection = _controller.selection;
                if (selection != null) {
                  final text = _terminal.buffer.getText(selection);
                  _controller.clearSelection();
                  await Clipboard.setData(ClipboardData(text: text));
                } else {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text;
                  if (text != null) {
                    _terminal.paste(text);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// ANSI colours come from the palette, but `black`/`white` and the search-hit
  /// foreground have to invert with brightness — a black-on-white terminal
  /// needs the opposite ends of the ramp from a white-on-black one.
  static TerminalTheme _studioTheme(AppPalette palette) {
    final isDark = palette.isDark;
    return TerminalTheme(
      cursor: palette.accent,
      selection: palette.accent.withValues(alpha: 0.33),
      foreground: palette.textPrimary,
      background: palette.rail,
      black: isDark ? const Color(0xFF000000) : const Color(0xFF3B3B3B),
      red: palette.error,
      green: palette.success,
      yellow: palette.warning,
      blue: palette.info,
      magenta: isDark ? const Color(0xFFBC3FBC) : const Color(0xFF9B2A9B),
      cyan: palette.accent,
      white: isDark ? palette.textPrimary : const Color(0xFF6E6E6E),
      brightBlack: palette.textMuted,
      brightRed: palette.error,
      brightGreen: palette.success,
      brightYellow: palette.warning,
      brightBlue: palette.info,
      brightMagenta: isDark ? const Color(0xFFD670D6) : const Color(0xFFB93EB9),
      brightWhite: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1F1F1F),
      brightCyan: palette.accent,
      searchHitBackground: palette.warning,
      searchHitBackgroundCurrent: palette.success,
      searchHitForeground: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF),
    );
  }
}
