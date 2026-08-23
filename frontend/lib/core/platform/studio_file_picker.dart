import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Folder/file dialogs that work with Robot Studio's **non-sandboxed** macOS
/// build.
///
/// `file_picker` refuses to open `NSOpenPanel` unless the User Selected File
/// entitlement is active. That entitlement only applies inside App Sandbox,
/// which Studio keeps off (Terminal, Robot runs, arbitrary project roots).
/// On macOS we therefore drive the panels ourselves; other platforms keep
/// using `file_picker`.
class StudioFilePicker {
  StudioFilePicker._();

  static const _channel = MethodChannel('robot_studio/file_picker');

  static Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    if (!kIsWeb && Platform.isMacOS) {
      try {
        return await _channel.invokeMethod<String>('getDirectoryPath', {
          'dialogTitle': ?dialogTitle,
          'initialDirectory': ?initialDirectory,
        });
      } on MissingPluginException {
        // Widget tests / hosts without the Runner channel.
      }
    }
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );
  }

  static Future<String?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    if (!kIsWeb && Platform.isMacOS) {
      try {
        return await _channel.invokeMethod<String>('pickFile', {
          'dialogTitle': ?dialogTitle,
          'initialDirectory': ?initialDirectory,
          'allowedExtensions': ?allowedExtensions,
        });
      } on MissingPluginException {
        // Widget tests / hosts without the Runner channel.
      }
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  static Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    if (!kIsWeb && Platform.isMacOS) {
      try {
        return await _channel.invokeMethod<String>('saveFile', {
          'dialogTitle': ?dialogTitle,
          'fileName': ?fileName,
          'initialDirectory': ?initialDirectory,
          'allowedExtensions': ?allowedExtensions,
        });
      } on MissingPluginException {
        // Widget tests / hosts without the Runner channel.
      }
    }
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: initialDirectory,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
  }
}
