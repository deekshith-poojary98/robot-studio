import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:vscode_material_icon_theme/vscode_material_icon_theme.dart';

import '../../core/theme/app_theme.dart';

/// VS Code Material Icon Theme glyphs for explorer rows.
///
/// Uses [SvgPicture] with compiled `.vec` loaders (same as the package docs).
/// Shows a Material Icon placeholder while loading so the explorer never looks
/// empty after a hot-reload before assets are available.
Widget explorerFileIcon({
  required String name,
  bool isDirectory = false,
  bool expanded = false,
  bool loading = false,
  double size = 16,
}) {
  final fallback = Icon(
    loading
        ? Icons.hourglass_empty
        : isDirectory
            ? (expanded ? Icons.folder_open_outlined : Icons.folder_outlined)
            : Icons.insert_drive_file_outlined,
    size: size,
    color: AppColors.textSecondary,
  );

  if (loading) return fallback;

  final key = name.trim().toLowerCase();
  final loader = isDirectory
      ? directoryToIcon(
          key.isEmpty ? '/' : key,
          isExpanded: expanded,
        )
      : _fileLoader(key);

  return SvgPicture(
    loader,
    width: size,
    height: size,
    fit: BoxFit.contain,
    allowDrawingOutsideViewBox: true,
    placeholderBuilder: (_) => fallback,
  );
}

AssetBytesLoader _fileLoader(String lowerName) {
  if (lowerName.isEmpty) return MaterialIcons.file;
  if (lowerName.endsWith('.resource')) return MaterialIcons.robot;
  return fileToIcon(lowerName);
}
