import 'package:flutter_test/flutter_test.dart';
import 'package:pod_quick/models/app_settings.dart';
import 'package:pod_quick/models/clipboard_item.dart';
import 'package:pod_quick/services/app_state.dart';

void main() {
  test('Placeholder Test', () {
    expect(true, isTrue);
  });

  test('AppSettings persists panel order', () {
    final settings = AppSettings(
      panelOrder: const [PanelPane.notes, PanelPane.clipboard, PanelPane.files],
    );

    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.panelOrder, [
      PanelPane.notes,
      PanelPane.clipboard,
      PanelPane.files,
    ]);
  });

  test('AppSettings repairs incomplete panel order', () {
    final restored = AppSettings.fromJson({
      'panelOrder': ['notes', 'notes', 'unknown'],
    });

    expect(restored.panelOrder, [
      PanelPane.notes,
      PanelPane.clipboard,
      PanelPane.files,
    ]);
  });

  test('AppState isItemFavorite image/text favorites check', () {
    final state = AppState();
    state.clipboardFavorites.clear();

    final textItem = ClipboardItem(
      id: 'text-1',
      content: 'Hello',
      timestamp: DateTime.now(),
    );
    final imageItem1 = ClipboardItem(
      id: 'img-1',
      content: '[图片]',
      imagePath: 'clipboard_images/img-1.png',
      imageSignature: '100:12345',
      timestamp: DateTime.now(),
    );
    final imageItem2 = ClipboardItem(
      id: 'img-2',
      content: '[图片]',
      imagePath: 'clipboard_images/img-2.png',
      imageSignature: '100:67890',
      timestamp: DateTime.now(),
    );

    // Initially none are favorites
    expect(state.isItemFavorite(textItem), isFalse);
    expect(state.isItemFavorite(imageItem1), isFalse);
    expect(state.isItemFavorite(imageItem2), isFalse);

    // Add text item to favorites
    state.clipboardFavorites.add(textItem);
    expect(state.isItemFavorite(textItem), isTrue);

    // Add imageItem1 to favorites
    state.clipboardFavorites.add(imageItem1);
    expect(state.isItemFavorite(imageItem1), isTrue);
    // Since imageItem2 has different signature/id, it should NOT be favorite!
    expect(state.isItemFavorite(imageItem2), isFalse);

    // Clean up
    state.clipboardFavorites.clear();
  });
}
