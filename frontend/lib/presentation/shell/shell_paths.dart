/// Path comparison helpers for shell session lifecycle.
bool sameFsPath(String? a, String? b) {
  if (a == null || b == null) return false;
  final left = a.trim().replaceAll('\\', '/').toLowerCase();
  final right = b.trim().replaceAll('\\', '/').toLowerCase();
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  final leftTrim =
      left.endsWith('/') ? left.substring(0, left.length - 1) : left;
  final rightTrim =
      right.endsWith('/') ? right.substring(0, right.length - 1) : right;
  return leftTrim == rightTrim;
}
