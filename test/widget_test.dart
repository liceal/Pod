import 'package:flutter_test/flutter_test.dart';
import 'package:pod/models/app_settings.dart';

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
}
