import 'package:flutter_test/flutter_test.dart';
import 'package:robot_studio/core/gateway/models/library_info.dart';
import 'package:robot_studio/presentation/libraries/library_explorer_controller.dart';

void main() {
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

  test('openLibrary explains missing package when resolve returns empty', () async {
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
  });
}
