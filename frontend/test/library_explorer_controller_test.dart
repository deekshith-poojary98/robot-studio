import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/library_info.dart';
import 'package:robot_studio/presentation/libraries/library_explorer_controller.dart';

void main() {
  test('doc_format survives the REST hop so the renderer can use it', () {
    final library = LibraryInfo.fromJson(const {
      'name': 'MarkdownLibrary',
      'doc_format': 'MARKDOWN',
      'keywords': [
        {
          'name': 'Add Sheet',
          'documentation': 'Adds a **new sheet**.',
          'doc_format': 'MARKDOWN',
        },
      ],
    });

    expect(library.docFormat, 'MARKDOWN');
    expect(library.keywords.single.docFormat, 'MARKDOWN');

    // Older payloads have no doc_format; those must stay sniffable.
    final legacy = LibraryInfo.fromJson(const {'name': 'BuiltIn'});
    expect(legacy.docFormat, '');
  });

  test('filteredKeywords is substring match owned by controller', () async {
    final controller = LibraryExplorerController(
      listLibraries: () async => [
        const LibraryInfo(name: 'BuiltIn', builtin: true, keywordCount: 2),
      ],
      getLibrary: (name) async => LibraryInfo(
        name: name,
        builtin: true,
        keywordCount: 2,
        keywords: const [
          LibraryKeywordInfo(name: 'Log', documentation: 'Logs a message'),
          LibraryKeywordInfo(name: 'Should Be Equal'),
        ],
      ),
    );

    await controller.loadLibraries();
    await controller.openLibrary(controller.libraries.first);
    expect(controller.filteredKeywords.length, 2);

    controller.setKeywordFilter('log');
    expect(controller.filteredKeywords.map((k) => k.name), ['Log']);

    controller.openKeyword(controller.filteredKeywords.first);
    expect(controller.level, LibraryExplorerLevel.detail);
    expect(controller.selectedKeyword?.name, 'Log');

    controller.back();
    expect(controller.level, LibraryExplorerLevel.keywords);
    controller.back();
    expect(controller.level, LibraryExplorerLevel.libraries);
  });

  test(
    'openLibrary explains missing package when resolve returns empty',
    () async {
      final controller = LibraryExplorerController(
        listLibraries: () async => [
          const LibraryInfo(name: 'Browser', keywordCount: 0),
        ],
        getLibrary: (_) async => null,
      );

      await controller.loadLibraries();
      await controller.openLibrary(controller.libraries.first);
      expect(controller.error, contains('not installed'));
      expect(controller.error, contains('Browser'));
    },
  );
}
