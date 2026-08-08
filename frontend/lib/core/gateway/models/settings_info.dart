/// Typed application preferences — mirror of backend AppSettings.
library;

import '../../theme/app_accent.dart';

export '../../theme/app_accent.dart' show AppAccentPreference;

class EditorSettings {
  const EditorSettings({
    this.autoSave = false,
    this.saveBeforeRun = true,
    this.tabWidth = 4,
    this.insertSpaces = true,
    this.wordWrap = true,
    this.fontSize = 13,
    this.fontFamily = 'Menlo',
  });

  factory EditorSettings.fromJson(Map<String, dynamic> json) {
    return EditorSettings(
      autoSave: json['auto_save'] as bool? ?? false,
      saveBeforeRun: json['save_before_run'] as bool? ?? true,
      tabWidth: (json['tab_width'] as num?)?.toInt() ?? 4,
      insertSpaces: json['insert_spaces'] as bool? ?? true,
      wordWrap: json['word_wrap'] as bool? ?? true,
      fontSize: (json['font_size'] as num?)?.toInt() ?? 13,
      fontFamily: (json['font_family'] as String?)?.trim().isNotEmpty == true
          ? (json['font_family'] as String).trim()
          : 'Menlo',
    );
  }

  final bool autoSave;
  final bool saveBeforeRun;
  final int tabWidth;
  final bool insertSpaces;
  final bool wordWrap;
  final int fontSize;
  final String fontFamily;

  Map<String, dynamic> toJson() => {
    'auto_save': autoSave,
    'save_before_run': saveBeforeRun,
    'tab_width': tabWidth,
    'insert_spaces': insertSpaces,
    'word_wrap': wordWrap,
    'font_size': fontSize,
    'font_family': fontFamily,
  };

  EditorSettings copyWith({
    bool? autoSave,
    bool? saveBeforeRun,
    int? tabWidth,
    bool? insertSpaces,
    bool? wordWrap,
    int? fontSize,
    String? fontFamily,
  }) {
    return EditorSettings(
      autoSave: autoSave ?? this.autoSave,
      saveBeforeRun: saveBeforeRun ?? this.saveBeforeRun,
      tabWidth: tabWidth ?? this.tabWidth,
      insertSpaces: insertSpaces ?? this.insertSpaces,
      wordWrap: wordWrap ?? this.wordWrap,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}

class ExecutionSettings {
  const ExecutionSettings({
    this.largeRunThreshold = 100,
    this.revealExecutionOnRun = true,
    this.autoOpenReportOnFailure = false,
    this.stopConfirmation = true,
  });

  factory ExecutionSettings.fromJson(Map<String, dynamic> json) {
    return ExecutionSettings(
      largeRunThreshold: (json['large_run_threshold'] as num?)?.toInt() ?? 100,
      revealExecutionOnRun: json['reveal_execution_on_run'] as bool? ?? true,
      autoOpenReportOnFailure:
          json['auto_open_report_on_failure'] as bool? ?? false,
      stopConfirmation: json['stop_confirmation'] as bool? ?? true,
    );
  }

  final int largeRunThreshold;
  final bool revealExecutionOnRun;
  final bool autoOpenReportOnFailure;
  final bool stopConfirmation;

  Map<String, dynamic> toJson() => {
    'large_run_threshold': largeRunThreshold,
    'reveal_execution_on_run': revealExecutionOnRun,
    'auto_open_report_on_failure': autoOpenReportOnFailure,
    'stop_confirmation': stopConfirmation,
  };

  ExecutionSettings copyWith({
    int? largeRunThreshold,
    bool? revealExecutionOnRun,
    bool? autoOpenReportOnFailure,
    bool? stopConfirmation,
  }) {
    return ExecutionSettings(
      largeRunThreshold: largeRunThreshold ?? this.largeRunThreshold,
      revealExecutionOnRun: revealExecutionOnRun ?? this.revealExecutionOnRun,
      autoOpenReportOnFailure:
          autoOpenReportOnFailure ?? this.autoOpenReportOnFailure,
      stopConfirmation: stopConfirmation ?? this.stopConfirmation,
    );
  }
}

class SearchSettings {
  const SearchSettings({
    this.contentSearchExtensions = const [
      '.robot',
      '.resource',
      '.py',
      '.yaml',
      '.yml',
      '.txt',
      '.md',
      '.json',
      '.tsv',
      '.csv',
    ],
    this.ignorePatterns = const [
      '.git',
      '.venv',
      'venv',
      'node_modules',
      '__pycache__',
      '.robotstudio',
      '.DS_Store',
    ],
  });

  factory SearchSettings.fromJson(Map<String, dynamic> json) {
    return SearchSettings(
      contentSearchExtensions: _stringList(json['content_search_extensions']),
      ignorePatterns: _stringList(json['ignore_patterns']),
    );
  }

  final List<String> contentSearchExtensions;
  final List<String> ignorePatterns;

  Map<String, dynamic> toJson() => {
    'content_search_extensions': contentSearchExtensions,
    'ignore_patterns': ignorePatterns,
  };

  SearchSettings copyWith({
    List<String>? contentSearchExtensions,
    List<String>? ignorePatterns,
  }) {
    return SearchSettings(
      contentSearchExtensions:
          contentSearchExtensions ?? this.contentSearchExtensions,
      ignorePatterns: ignorePatterns ?? this.ignorePatterns,
    );
  }
}

class AppearanceSettings {
  const AppearanceSettings({
    this.theme = AppThemePreference.dark,
    this.accent = AppAccentPreference.teal,
    this.restoreLastProject = true,
  });

  factory AppearanceSettings.fromJson(Map<String, dynamic> json) {
    return AppearanceSettings(
      theme: AppThemePreference.fromApi(json['theme'] as String? ?? 'dark'),
      accent: AppAccentPreference.fromApi(
        json['accent'] as String? ?? 'teal',
      ),
      restoreLastProject: json['restore_last_project'] as bool? ?? true,
    );
  }

  final AppThemePreference theme;
  final AppAccentPreference accent;
  final bool restoreLastProject;

  Map<String, dynamic> toJson() => {
        'theme': theme.apiValue,
        'accent': accent.apiValue,
        'restore_last_project': restoreLastProject,
      };

  AppearanceSettings copyWith({
    AppThemePreference? theme,
    AppAccentPreference? accent,
    bool? restoreLastProject,
  }) {
    return AppearanceSettings(
      theme: theme ?? this.theme,
      accent: accent ?? this.accent,
      restoreLastProject: restoreLastProject ?? this.restoreLastProject,
    );
  }
}

enum AppThemePreference {
  dark,
  light,
  system;

  static AppThemePreference fromApi(String value) {
    return switch (value.toLowerCase()) {
      'light' => AppThemePreference.light,
      'system' => AppThemePreference.system,
      _ => AppThemePreference.dark,
    };
  }

  String get apiValue => switch (this) {
    AppThemePreference.dark => 'dark',
    AppThemePreference.light => 'light',
    AppThemePreference.system => 'system',
  };

  String get label => switch (this) {
    AppThemePreference.dark => 'Dark',
    AppThemePreference.light => 'Light',
    AppThemePreference.system => 'System',
  };
}

class AppSettings {
  const AppSettings({
    this.version = 1,
    this.editor = const EditorSettings(),
    this.execution = const ExecutionSettings(),
    this.search = const SearchSettings(),
    this.appearance = const AppearanceSettings(),
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      version: (json['version'] as num?)?.toInt() ?? 1,
      editor: EditorSettings.fromJson(
        (json['editor'] as Map<String, dynamic>?) ?? const {},
      ),
      execution: ExecutionSettings.fromJson(
        (json['execution'] as Map<String, dynamic>?) ?? const {},
      ),
      search: SearchSettings.fromJson(
        (json['search'] as Map<String, dynamic>?) ?? const {},
      ),
      appearance: AppearanceSettings.fromJson(
        (json['appearance'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  final int version;
  final EditorSettings editor;
  final ExecutionSettings execution;
  final SearchSettings search;
  final AppearanceSettings appearance;

  Map<String, dynamic> toJson() => {
    'version': version,
    'editor': editor.toJson(),
    'execution': execution.toJson(),
    'search': search.toJson(),
    'appearance': appearance.toJson(),
  };

  AppSettings copyWith({
    EditorSettings? editor,
    ExecutionSettings? execution,
    SearchSettings? search,
    AppearanceSettings? appearance,
  }) {
    return AppSettings(
      version: version,
      editor: editor ?? this.editor,
      execution: execution ?? this.execution,
      search: search ?? this.search,
      appearance: appearance ?? this.appearance,
    );
  }
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
