/// Lets [AppShell] ask the open Settings page whether it is safe to leave.
///
/// [PreferencesPage] binds while mounted; the shell calls [confirmLeave] /
/// [savePending] before navigation or quit.
class PreferencesLeaveBinding {
  Future<bool> Function()? _confirmLeave;
  Future<bool> Function()? _savePending;
  bool Function()? _isDirty;

  void bind({
    required Future<bool> Function() confirmLeave,
    required Future<bool> Function() savePending,
    required bool Function() isDirty,
  }) {
    _confirmLeave = confirmLeave;
    _savePending = savePending;
    _isDirty = isDirty;
  }

  void unbind() {
    _confirmLeave = null;
    _savePending = null;
    _isDirty = null;
  }

  bool get isDirty => _isDirty?.call() ?? false;

  /// Save / Discard / Cancel. Returns `true` when the shell may leave Settings.
  Future<bool> confirmLeave() async {
    final handler = _confirmLeave;
    if (handler == null) return true;
    return handler();
  }

  /// Persist the draft without discarding. Returns `false` on failure.
  Future<bool> savePending() async {
    if (!isDirty) return true;
    final handler = _savePending;
    if (handler == null) return true;
    return handler();
  }
}
