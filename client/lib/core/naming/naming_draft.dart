import 'file_naming.dart';

class NamingField {
  const NamingField(this.id, this.name);
  final int id;
  final String name;
}

/// Preserves existing literal text, including nonuniform separators, on load.
class NamingDraft {
  NamingDraft(String template) {
    final error = FileNaming.validateTemplate(template);
    if (error != null) throw FormatException(error);
    var end = 0;
    for (final match in RegExp(r'\{(\w+)\}').allMatches(template)) {
      final literal = template.substring(end, match.start);
      if (_fields.isEmpty) {
        _prefix = literal;
      } else {
        _gaps.add(literal);
      }
      _fields.add(NamingField(_nextId++, match[1]!));
      end = match.end;
    }
    if (_fields.isEmpty) {
      _prefix = template;
    } else {
      _suffix = template.substring(end);
    }
    if (_gaps.isNotEmpty) separator = _gaps.first;
  }
  final _fields = <NamingField>[];
  final _gaps = <String>[];
  int _nextId = 0;
  String _prefix = '', _suffix = '';
  String separator = '_';
  List<NamingField> get fields => List.unmodifiable(_fields);
  List<String> get separators => List.unmodifiable(_gaps);
  String get template {
    final out = StringBuffer(_prefix);
    for (var i = 0; i < _fields.length; i++) {
      if (i > 0) out.write(_gaps[i - 1]);
      out.write('{${_fields[i].name}}');
    }
    return '$out$_suffix';
  }

  void add(String name) {
    if (!FileNaming.variables.contains(name)) throw ArgumentError.value(name);
    if (_fields.isNotEmpty) _gaps.add(separator);
    _fields.add(NamingField(_nextId++, name));
  }

  void setSeparator(String value) {
    if (value.contains(RegExp(r'[{}<>:"/\\|?*\x00-\x1f]'))) {
      throw const FormatException('分隔符不能包含文件名非法字符或花括号');
    }
    if (value.runes.length > 16) throw const FormatException('分隔符最多16字');
    separator = value;
    for (var i = 0; i < _gaps.length; i++) {
      _gaps[i] = value;
    }
  }

  void remove(int index) {
    _fields.removeAt(index);
    if (_gaps.isNotEmpty) _gaps.removeAt(index == 0 ? 0 : index - 1);
  }

  void move(int from, int to) {
    final field = _fields.removeAt(from);
    _fields.insert(to, field);
  }
}
