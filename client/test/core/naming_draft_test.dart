import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/core/naming/naming_draft.dart';
import 'package:xdownloader/core/naming/file_naming.dart';

void main() {
  test('tag editor preserves legacy prefixes separators suffixes and repeated fields until changed', () {
    for (final raw in [
      FileNaming.defaultTemplate,
      '前缀-{title}__{date}.mp4',
      '{title}{title}',
      '固定文件名',
    ]) {
      expect(NamingDraft(raw).template, raw);
    }
  });
  test('click append separator and reorder compose valid templates without touching the saved rule', () {
    final draft = NamingDraft('{title}_{date}');
    draft.add('time');
    expect(draft.template, '{title}_{date}_{time}');
    draft.setSeparator('-');
    draft.move(2, 0);
    expect(draft.template, '{time}-{title}-{date}');
    draft.remove(1);
    expect(draft.template, '{time}-{date}');
    expect(FileNaming.validateTemplate(draft.template), isNull);
    expect(() => draft.add('unknown'), throwsArgumentError);
    expect(() => draft.setSeparator('{'), throwsFormatException);
  });
}
