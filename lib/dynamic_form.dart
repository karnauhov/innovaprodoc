// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:innovaprodoc/storage_backend.dart';
import 'package:innovaprodoc/timer_handle.dart';

class DynamicForm extends StatefulWidget {
  final Map<String, dynamic> schema;
  const DynamicForm({super.key, required this.schema});

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> values = {};
  final Map<String, TextEditingController> controllers = {};
  final Map<String, List<Map<String, dynamic>>> repeaterData = {};
  final Map<String, int> seqCounters = {};
  TimerHandle? autosaveTimer;
  bool autosaveEnabled = false;
  int autosaveDebounceMs = 700;
  String? storageKey;
  Map<String, dynamic> enums = {};
  Map<String, dynamic> schema = {};
  late StorageBackend storage;

  @override
  void initState() {
    super.initState();
    storage = StorageBackend();
    schema = widget.schema;
    enums = Map<String, dynamic>.from(schema['enums'] ?? {});
    _initDataModel();
  }

  void _initDataModel() {
    final dataModel = schema['dataModel'] ?? {};
    dataModel.forEach((k, def) {
      final defMap = def is Map ? def : {};
      if (defMap.containsKey('default')) {
        final defaultExpr = defMap['default'];
        if (defaultExpr is String && _isExpression(defaultExpr)) {
          values[k] = _computeExpression(defaultExpr);
        } else {
          values[k] = defMap['default'];
        }
      }
      if (!values.containsKey(k)) values[k] = null;
    });

    for (var s in (schema['sections'] as List<dynamic>? ?? [])) {
      final sec = s as Map<String, dynamic>;
      for (var f in (sec['fields'] as List<dynamic>? ?? [])) {
        final fm = f as Map<String, dynamic>;
        final key = fm['key'];
        if (fm['type'] != 'repeater') {
          controllers.putIfAbsent(
            key,
            () => TextEditingController(
              text: _initialTextForField(fm, values[key]),
            ),
          );
          if (fm.containsKey('computed')) {
            final comp = fm['computed'];
            if (comp is String && _isExpression(comp)) {
              controllers[key]!.text = _computeExpression(comp);
              values[key] = controllers[key]!.text;
            }
          } else if (fm.containsKey('default')) {
            final d = fm['default'];
            if (d is String && _isExpression(d)) {
              controllers[key]!.text = _computeExpression(d);
              values[key] = controllers[key]!.text;
            } else if (d != null) {
              controllers[key]!.text = d.toString();
              values[key] = d;
            }
          }
        } else {
          repeaterData[key] = [];
        }
      }
    }

    final bs = schema['behavior']?['autosave'] ?? {};
    autosaveEnabled = bs['enabled'] == true;
    autosaveDebounceMs = bs['debounceMs'] ?? autosaveDebounceMs;
    final templ = bs['storageKeyTemplate'] ?? '';
    if (templ is String && templ.contains('\${')) {
      storageKey = templ.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (m) {
        final expr = m.group(1)!;
        return _computeExpression('\${$expr}');
      });
    } else {
      storageKey = templ.toString();
    }
    _tryRestore();
  }

  String _initialTextForField(Map<String, dynamic> fm, dynamic currentValue) {
    if (currentValue != null) return currentValue.toString();
    if (fm.containsKey('default')) {
      final d = fm['default'];
      if (d is String && _isExpression(d)) {
        return _computeExpression(d);
      } else if (d != null) {
        return d.toString();
      }
    }
    return '';
  }

  void _tryRestore() {
    if (storageKey != null && storageKey!.isNotEmpty) {
      try {
        final s = storage.getItem(storageKey!);
        if (s != null) {
          final map = json.decode(s) as Map<String, dynamic>;
          map.forEach((k, v) {
            values[k] = v;
            if (controllers.containsKey(k)) {
              controllers[k]!.text = v?.toString() ?? '';
            }
            if (repeaterData.containsKey(k) && v is List) {
              repeaterData[k] = v
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  storage.usesLocalStorage()
                      ? 'Чернетка відновлена з localStorage'
                      : 'Чернетка відновлена з in-memory fallback',
                ),
              ),
            );
            setState(() {});
          });
        }
      } catch (e) {
        //print('restore failed: $e');
      }
    }
  }

  bool _isExpression(String s) => s.contains(r'${');

  dynamic _computeExpression(String template) {
    final m = RegExp(r'\$\{(.*)\}').firstMatch(template);
    if (m == null) return template;
    final expr = m.group(1)!.trim();
    final parts = _splitPlus(expr);
    String out = '';
    for (var part in parts) {
      part = part.trim();
      if (part.startsWith("'") && part.endsWith("'")) {
        out += part.substring(1, part.length - 1);
      } else if (part.contains(RegExp(r'^\d+$'))) {
        out += part;
      } else if (part.startsWith("year(")) {
        final inner = _innerOf(part, 'year');
        if (inner != null) {
          final val = _evalFunction(inner.trim());
          if (val is DateTime) {
            out += val.year.toString();
          } else if (val is String) {
            try {
              final dt = DateTime.parse(val);
              out += dt.year.toString();
            } catch (_) {
              out += val;
            }
          } else {
            out += val.toString();
          }
        }
      } else if (part.startsWith("pad(")) {
        final inner = _innerOf(part, 'pad');
        if (inner != null) {
          final args = _splitArgs(inner);
          final n = int.tryParse(_evalFunctionOrValue(args[0]).toString()) ?? 0;
          final len =
              int.tryParse(_evalFunctionOrValue(args[1]).toString()) ?? 0;
          out += n.toString().padLeft(len, '0');
        }
      } else if (part.startsWith("seq(")) {
        final inner = _innerOf(part, 'seq');
        if (inner != null) {
          final name = inner.trim();
          final key = name.replaceAll("'", "").replaceAll('"', '');
          seqCounters[key] = (seqCounters[key] ?? 0) + 1;
          out += seqCounters[key].toString();
        }
      } else if (part.startsWith("now()") || part == 'now()') {
        out += DateTime.now().toIso8601String();
      } else if (part.startsWith("today()") || part == 'today()') {
        final d = DateTime.now();
        out += '${d.year}-${_two(d.month)}-${_two(d.day)}';
      } else if (part.startsWith("uuid()") || part == 'uuid()') {
        out += _genUuid();
      } else {
        final val = values[part];
        if (val != null) out += val.toString();
      }
    }
    return out;
  }

  String _two(int n) => n < 10 ? '0$n' : '$n';

  String _genUuid() {
    final r = Random();
    return List<int>.generate(
      16,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String? _innerOf(String s, String fn) {
    final re = RegExp(r'\b' + RegExp.escape(fn) + r'\((.*)\)$');
    final m = re.firstMatch(s);
    return m?.group(1);
  }

  List<String> _splitPlus(String expr) {
    List<String> res = [];
    String cur = '';
    bool inQuote = false;
    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == "'" && (i == 0 || expr[i - 1] != '\\')) {
        inQuote = !inQuote;
        cur += ch;
      } else if (ch == '+' && !inQuote) {
        res.add(cur);
        cur = '';
      } else {
        cur += ch;
      }
    }
    if (cur.isNotEmpty) res.add(cur);
    return res;
  }

  dynamic _evalFunction(String code) {
    code = code.trim();
    if (code == 'now()') return DateTime.now();
    if (code == 'today()') return DateTime.now().toIso8601String();
    if (code.startsWith('now(') || code.startsWith('today(')) {
      return DateTime.now();
    }
    if (code.startsWith("'") && code.endsWith("'")) {
      return code.substring(1, code.length - 1);
    }
    if (values.containsKey(code)) {
      return values[code];
    }
    return code;
  }

  dynamic _evalFunctionOrValue(String token) {
    token = token.trim();
    if (token.startsWith("'") && token.endsWith("'")) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'now()') return DateTime.now();
    if (values.containsKey(token)) return values[token];
    return token;
  }

  List<String> _splitArgs(String s) {
    List<String> res = [];
    String cur = '';
    bool inQuote = false;
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == "'" && (i == 0 || s[i - 1] != '\\')) {
        inQuote = !inQuote;
        cur += ch;
      } else if (ch == ',' && !inQuote) {
        res.add(cur.trim());
        cur = '';
      } else {
        cur += ch;
      }
    }
    if (cur.trim().isNotEmpty) res.add(cur.trim());
    return res;
  }

  bool evaluateBoolExpression(
    String template, {
    Map<String, dynamic>? localScope,
  }) {
    final m = RegExp(r'\$\{(.*)\}').firstMatch(template);
    if (m == null) return false;
    String expr = m.group(1)!;
    expr = expr.trim();
    List<String> ors = _splitByTopLevel(expr, '||');
    for (var orPart in ors) {
      final andParts = _splitByTopLevel(orPart, '&&');
      bool andRes = true;
      for (var ap in andParts) {
        final trimmed = ap.trim();
        if (trimmed.isEmpty) continue;
        bool partRes = _evalComparison(trimmed, localScope: localScope);
        andRes = andRes && partRes;
      }
      if (andRes) return true;
    }
    return false;
  }

  List<String> _splitByTopLevel(String s, String delim) {
    List<String> res = [];
    int idx = 0;
    int last = 0;
    while (idx < s.length) {
      if (s.startsWith(delim, idx)) {
        res.add(s.substring(last, idx));
        idx += delim.length;
        last = idx;
        continue;
      }
      if (s[idx] == "'") {
        idx++;
        while (idx < s.length && s[idx] != "'") {
          idx++;
        }
        idx++;
        continue;
      }
      idx++;
    }
    res.add(s.substring(last));
    return res;
  }

  bool _evalComparison(String cmp, {Map<String, dynamic>? localScope}) {
    var s = cmp.trim();
    if (s.contains('==')) {
      final parts = s.split('==');
      final l = parts[0].trim();
      final r = parts.sublist(1).join('==').trim();
      final lv = _resolveValue(l, localScope);
      final rv = _parseLiteralOrValue(r, localScope);
      return (lv?.toString() ?? '') == (rv?.toString() ?? '');
    } else if (s.contains('!=')) {
      final parts = s.split('!=');
      final l = parts[0].trim();
      final r = parts.sublist(1).join('!=').trim();
      final lv = _resolveValue(l, localScope);
      final rv = _parseLiteralOrValue(r, localScope);
      return (lv?.toString() ?? '') != (rv?.toString() ?? '');
    } else {
      final v = _resolveValue(s, localScope);
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return v != null;
    }
  }

  dynamic _resolveValue(String token, Map<String, dynamic>? localScope) {
    token = token.trim();
    if (token.startsWith("'") && token.endsWith("'")) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') return true;
    if (token == 'false') return false;
    if (token.startsWith('year(')) {
      final inner = _innerOf(token, 'year');
      if (inner != null) {
        final innerVal = _evalFunction(inner.trim());
        if (innerVal is DateTime) return innerVal.year;
        if (innerVal is String) {
          try {
            final dt = DateTime.parse(innerVal);
            return dt.year;
          } catch (_) {}
        }
      }
    }
    if (localScope != null && localScope.containsKey(token)) {
      return localScope[token];
    }
    return values[token];
  }

  dynamic _parseLiteralOrValue(String token, Map<String, dynamic>? localScope) {
    token = token.trim();
    if (token.startsWith("'") && token.endsWith("'")) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') {
      return true;
    }
    if (token == 'false') {
      return false;
    }
    return _resolveValue(token, localScope);
  }

  void onFieldChanged(String key, dynamic value) {
    values[key] = value;
    if (controllers.containsKey(key)) {
      controllers[key]!.text = value?.toString() ?? '';
    }
    _recomputeComputedFields();
    if (autosaveEnabled) {
      autosaveTimer?.cancel();
      autosaveTimer = TimerHandle(() {
        _saveDraftToLocal();
      }, autosaveDebounceMs);
    }
    setState(() {});
  }

  void _recomputeComputedFields() {
    for (var s in (schema['sections'] as List<dynamic>? ?? [])) {
      final sec = s as Map<String, dynamic>;
      for (var f in (sec['fields'] as List<dynamic>? ?? [])) {
        final fm = f as Map<String, dynamic>;
        final key = fm['key'];
        if (fm.containsKey('computed')) {
          final comp = fm['computed'];
          if (comp is String && _isExpression(comp)) {
            final val = _computeExpression(comp);
            values[key] = val;
            if (controllers.containsKey(key)) {
              controllers[key]!.text = val?.toString() ?? '';
            }
          }
        }
      }
    }
  }

  void _saveDraftToLocal() {
    if (storageKey == null || storageKey!.isEmpty) return;
    final snapshot = <String, dynamic>{};
    snapshot.addAll(values);
    repeaterData.forEach((k, list) {
      snapshot[k] = list;
    });
    try {
      final encoded = json.encode(snapshot);
      storage.setItem(storageKey!, encoded);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            storage.usesLocalStorage()
                ? 'Чернетка збережена (localStorage)'
                : 'Чернетка збережена (in-memory fallback)',
          ),
        ),
      );
    } catch (e) {
      //print('save failed: $e');
    }
  }

  /// If localStorage isn't available, or user wants persistent copy,
  /// allow downloading the draft as a JSON file.
  void _exportDraftToFile() {
    final snapshot = <String, dynamic>{};
    snapshot.addAll(values);
    repeaterData.forEach((k, list) {
      snapshot[k] = list;
    });
    final content = JsonEncoder.withIndent('  ').convert(snapshot);
    final filename = '${storageKey ?? 'draft'}.json';
    final blob = html.Blob([content], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    // final a = html.AnchorElement(href: url)
    //   ..setAttribute('download', filename)
    //   ..click();
    html.Url.revokeObjectUrl(url);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Експортовано чернетку у файл $filename')),
    );
  }

  /// Import draft from a local file (user chooses file). Merges/overwrites values.
  void _importDraftFromFile() {
    final uploadInput = html.FileUploadInputElement()..accept = '.json';
    uploadInput.click();
    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files == null || files.isEmpty) return;
      final file = files[0];
      final reader = html.FileReader();
      reader.onLoad.first.then((_) {
        final result = reader.result;
        if (result is String) {
          try {
            final map = json.decode(result) as Map<String, dynamic>;
            // merge into values + repeaterData
            map.forEach((k, v) {
              if (repeaterData.containsKey(k) && v is List) {
                repeaterData[k] = v
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
              } else {
                values[k] = v;
                if (controllers.containsKey(k)) {
                  controllers[k]!.text = v?.toString() ?? '';
                }
              }
            });
            setState(() {});
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Імпортовано чернетку з файлу')),
            );
          } catch (err) {
            // ignore: use_build_context_synchronously
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Помилка парсингу файлу: $err')),
            );
          }
        } else {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не вдалося прочитати файл як текст')),
          );
        }
      });
      reader.onError.first.then((err) {
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text('Помилка читання файлу: $err')));
      });
      reader.readAsText(file);
    });
  }

  bool _validateForm() {
    final formState = _formKey.currentState;
    if (formState == null) return false;
    final ok = formState.validate();
    for (var s in (schema['sections'] as List<dynamic>? ?? [])) {
      final sec = s as Map<String, dynamic>;
      for (var f in (sec['fields'] as List<dynamic>? ?? [])) {
        final fm = f as Map<String, dynamic>;
        if (fm['type'] == 'repeater') {
          final key = fm['key'];
          final minItemsConds = (fm['minItemsWhen'] as List<dynamic>?) ?? [];
          for (var cond in minItemsConds) {
            final when = cond['when'];
            final min = cond['min'] ?? 0;
            if (when != null && evaluateBoolExpression(when)) {
              final count = repeaterData[key]?.length ?? 0;
              if (count < min) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Потрібно додати мінімум $min елементів у $key',
                    ),
                  ),
                );
              }
            }
          }
        }
      }
    }
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final sections = (schema['sections'] as List<dynamic>? ?? []);
    final actions = (schema['actions'] as List<dynamic>? ?? []);
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          // Top row: title + storage buttons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    schema['title'] ?? 'Form',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                // small indicator which backend is used
                Container(
                  margin: EdgeInsets.only(right: 8),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: storage.usesLocalStorage()
                        ? Colors.green[50]
                        : Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        storage.usesLocalStorage()
                            ? Icons.storage
                            : Icons.memory,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        storage.usesLocalStorage()
                            ? 'localStorage'
                            : 'in-memory',
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _saveDraftToLocal,
                  icon: Icon(Icons.save),
                  label: Text('Save draft'),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _exportDraftToFile,
                  icon: Icon(Icons.download),
                  label: Text('Save to file'),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _importDraftFromFile,
                  icon: Icon(Icons.upload),
                  label: Text('Load from file'),
                ),
              ],
            ),
          ),

          ...sections.map((s) => _buildSection(s as Map<String, dynamic>)),
          SizedBox(height: 20),
          Wrap(
            spacing: 12,
            children: actions.map((a) {
              final am = a as Map<String, dynamic>;
              if (am['type'] == 'localSave') {
                return ElevatedButton(
                  onPressed: () {
                    _saveDraftToLocal();
                  },
                  child: Text(am['label'] ?? 'Save'),
                );
              } else if (am['type'] == 'submit') {
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: () {
                    if (!_validateForm()) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Виправте помилки у формі')),
                      );
                      return;
                    }
                    values['status'] = 'SUBMITTED';
                    final onSuccess = am['onSuccess'] ?? {};
                    final toast = onSuccess['toast'] ?? 'Submitted';
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(toast)));
                    _saveDraftToLocal();
                  },
                  child: Text(am['label'] ?? 'Submit'),
                );
              } else {
                return ElevatedButton(
                  onPressed: () {},
                  child: Text(am['label'] ?? 'Action'),
                );
              }
            }).toList(),
          ),
          SizedBox(height: 24),
          Text(
            'Current model (debug):',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.grey[100],
            child: Text(
              JsonEncoder.withIndent(
                '  ',
              ).convert({'values': values, 'repeaters': repeaterData}),
            ),
          ),
          SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(Map<String, dynamic> sec) {
    final title = sec['title'] ?? sec['id'] ?? '';
    final visWhen = sec['visibleWhen'];
    final visible = visWhen == null ? true : evaluateBoolExpression(visWhen);
    if (!visible) {
      return SizedBox();
    }
    final fields = (sec['fields'] as List<dynamic>? ?? []);
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            ...fields.map((f) => _buildField(f as Map<String, dynamic>)),
          ],
        ),
      ),
    );
  }

  Widget _buildField(Map<String, dynamic> f) {
    final key = f['key'] as String;
    final type = f['type'] as String? ?? 'text';
    final label = f['label'] ?? key;
    final readOnly = f['readOnly'] == true;
    final visibleWhen = f['visibleWhen'];
    final visible = visibleWhen == null
        ? true
        : evaluateBoolExpression(visibleWhen);
    final required = f['required'] == true;
    final requiredWhen = f['requiredWhen'];
    final mustBeRequired = requiredWhen == null
        ? required
        : (evaluateBoolExpression(requiredWhen));
    if (!visible) return SizedBox();
    switch (type) {
      case 'text':
        controllers.putIfAbsent(
          key,
          () => TextEditingController(text: values[key]?.toString() ?? ''),
        );
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: controllers[key],
            readOnly: readOnly,
            decoration: InputDecoration(
              labelText: label,
              hintText: f['ui']?['hint'],
              border: OutlineInputBorder(),
            ),
            validator: (v) => _validateField(f, v),
            onChanged: (v) => onFieldChanged(key, v),
          ),
        );
      case 'multiline':
        controllers.putIfAbsent(
          key,
          () => TextEditingController(text: values[key]?.toString() ?? ''),
        );
        final minLines = f['ui']?['minLines'] ?? 3;
        final maxLines = f['ui']?['maxLines'] ?? 6;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: controllers[key],
            minLines: minLines,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
            ),
            validator: (v) => _validateField(f, v),
            onChanged: (v) => onFieldChanged(key, v),
          ),
        );
      case 'select':
        List<dynamic> options = [];
        if (f.containsKey('optionsRef')) {
          final ref = f['optionsRef'];
          options = enums[ref] ?? [];
        }
        final current = values[key] ?? f['default'];
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String>(
            initialValue: current?.toString(),
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
            ),
            items: options
                .map<DropdownMenuItem<String>>(
                  (opt) => DropdownMenuItem<String>(
                    value: opt['value'],
                    child: Text(opt['label'] ?? opt['value']),
                  ),
                )
                .toList(),
            onChanged: (v) => onFieldChanged(key, v),
            validator: (v) {
              if (mustBeRequired && (v == null || v.toString().isEmpty)) {
                return 'Обовʼязкове поле';
              }
              return null;
            },
          ),
        );
      case 'date':
        controllers.putIfAbsent(
          key,
          () => TextEditingController(text: values[key]?.toString() ?? ''),
        );
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: controllers[key],
            readOnly: true,
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today),
            ),
            validator: (v) => _validateField(f, v),
            onTap: () async {
              DateTime initial = DateTime.now();
              if (controllers[key]!.text.isNotEmpty) {
                try {
                  initial = DateTime.parse(controllers[key]!.text);
                } catch (_) {}
              }
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(1900),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                final iso = picked.toIso8601String();
                controllers[key]!.text = iso;
                onFieldChanged(key, iso);
              }
            },
          ),
        );
      case 'money':
        controllers.putIfAbsent(
          key,
          () => TextEditingController(text: values[key]?.toString() ?? ''),
        );
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: controllers[key],
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
              prefixText: '',
            ),
            validator: (v) => _validateField(f, v),
            onChanged: (v) {
              final numVal = double.tryParse(v.replaceAll(',', '.'));
              onFieldChanged(key, numVal);
            },
          ),
        );
      case 'bool':
        final val = values[key] ?? f['default'] ?? false;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: SwitchListTile(
            title: Text(label),
            value: val == true,
            onChanged: (v) {
              onFieldChanged(key, v);
            },
          ),
        );
      case 'attachments':
        final list = (values[key] is List)
            ? List<String>.from(values[key])
            : <String>[];
        values[key] = list;
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...list.map(
                    (fName) => Chip(
                      label: Text(fName),
                      onDeleted: () {
                        list.remove(fName);
                        onFieldChanged(key, list);
                      },
                    ),
                  ),
                  ActionChip(
                    label: Text(f['ui']?['addLabel'] ?? 'Додати файл'),
                    onPressed: () async {
                      final name = await showDialog<String>(
                        context: context,
                        builder: (ctx) {
                          String val = '';
                          return AlertDialog(
                            title: Text('Додати файл (імітація)'),
                            content: TextField(
                              onChanged: (v) => val = v,
                              decoration: InputDecoration(
                                hintText: 'Введіть імʼя файлу або URL',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text('Скасувати'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, val),
                                child: Text('Додати'),
                              ),
                            ],
                          );
                        },
                      );
                      if (name != null && name.isNotEmpty) {
                        list.add(name);
                        onFieldChanged(key, list);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      case 'repeater':
        final keyR = key;
        repeaterData.putIfAbsent(keyR, () => []);
        final items = repeaterData[keyR]!;
        final itemSchema = f['item'] as Map<String, dynamic>? ?? {};
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f['label'] ?? key,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              ...items.asMap().entries.map((entry) {
                final idx = entry.key;
                return Card(
                  color: Colors.grey[50],
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Елемент #${idx + 1}'),
                            TextButton.icon(
                              onPressed: () {
                                items.removeAt(idx);
                                onFieldChanged(keyR, items);
                              },
                              icon: Icon(Icons.delete, color: Colors.red),
                              label: Text(
                                'Видалити',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                        ...((itemSchema['fields'] as List<dynamic>? ?? []).map((
                          sf,
                        ) {
                          final sfm = sf as Map<String, dynamic>;
                          return _buildRepeaterItemField(keyR, idx, sfm);
                        }).toList()),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(height: 8),
              ElevatedButton.icon(
                icon: Icon(Icons.add),
                label: Text(f['ui']?['addLabel'] ?? 'Додати'),
                onPressed: () {
                  final newItem = <String, dynamic>{};
                  for (var sf
                      in (itemSchema['fields'] as List<dynamic>? ?? [])) {
                    final sfm = sf as Map<String, dynamic>;
                    if (sfm.containsKey('default')) {
                      newItem[sfm['key']] = sfm['default'];
                    } else {
                      newItem[sfm['key']] = null;
                    }
                  }
                  items.add(newItem);
                  onFieldChanged(keyR, items);
                },
              ),
            ],
          ),
        );
      default:
        return SizedBox();
    }
  }

  Widget _buildRepeaterItemField(
    String repeaterKey,
    int idx,
    Map<String, dynamic> fm,
  ) {
    final key = fm['key'] as String;
    final type = fm['type'] as String? ?? 'text';
    final label = fm['label'] ?? key;
    final local = repeaterData[repeaterKey]![idx];
    switch (type) {
      case 'text':
        final ctrlKey = '$repeaterKey:$idx:$key';
        controllers.putIfAbsent(
          ctrlKey,
          () => TextEditingController(text: local[key]?.toString() ?? ''),
        );
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            controller: controllers[ctrlKey],
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final validators = (fm['validators'] as List<dynamic>?) ?? [];
              for (var val in validators) {
                final rule = val['rule'];
                final value = val['value'];
                if (rule == 'minLength' && (v?.length ?? 0) < (value ?? 0)) {
                  return val['message'] ?? 'Too short';
                }
              }
              if ((fm['required'] == true) && (v == null || v.isEmpty)) {
                return 'Обовʼязкове поле';
              }
              return null;
            },
            onChanged: (v) {
              local[key] = v;
              onFieldChanged(repeaterKey, repeaterData[repeaterKey]);
            },
          ),
        );
      case 'select':
        List<dynamic> options = [];
        if (fm.containsKey('optionsRef')) {
          options = enums[fm['optionsRef']] ?? [];
        }
        final current = local[key] ?? fm['default'];
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String>(
            initialValue: current?.toString(),
            decoration: InputDecoration(
              labelText: label,
              border: OutlineInputBorder(),
            ),
            items: options
                .map<DropdownMenuItem<String>>(
                  (opt) => DropdownMenuItem<String>(
                    value: opt['value'],
                    child: Text(opt['label'] ?? opt['value']),
                  ),
                )
                .toList(),
            onChanged: (v) {
              local[key] = v;
              onFieldChanged(repeaterKey, repeaterData[repeaterKey]);
            },
            validator: (v) {
              if (fm['required'] == true && (v == null || v.isEmpty)) {
                return 'Обовʼязкове поле';
              }
              return null;
            },
          ),
        );
      default:
        return SizedBox();
    }
  }

  String? _validateField(Map<String, dynamic> f, String? v) {
    final validators = (f['validators'] as List<dynamic>?) ?? [];
    for (var val in validators) {
      final rule = val['rule'];
      final value = val['value'];
      final message = val['message'];
      switch (rule) {
        case 'minLength':
          if ((v?.length ?? 0) < (value ?? 0)) {
            return message ?? 'Занадто коротко';
          }
          break;
        case 'maxLength':
          if ((v?.length ?? 0) > (value ?? 0)) {
            return message ?? 'Занадто довго';
          }
          break;
        case 'email':
          final emailRe = RegExp(r'^[^@]+@[^@]+\.[^@]+');
          if (v == null || !emailRe.hasMatch(v)) {
            return message ?? 'Невірний email';
          }
          break;
        case 'gt':
          final numVal = double.tryParse(v ?? '');
          if (numVal == null || !(numVal > (value ?? 0))) {
            return message ?? 'Некоректне число';
          }
          break;
        case 'gteField':
          final other = val['field'];
          final otherVal = values[other];
          DateTime? dt1;
          DateTime? dt2;
          try {
            dt1 = v != null && v.isNotEmpty ? DateTime.parse(v) : null;
            dt2 = otherVal != null ? DateTime.parse(otherVal.toString()) : null;
          } catch (_) {}
          if (dt1 != null && dt2 != null && dt1.isBefore(dt2)) {
            return message ?? 'Дата повинна бути не раніше';
          }
          break;
        default:
          break;
      }
    }
    final must =
        (f['required'] == true) ||
        (f['requiredWhen'] != null &&
            evaluateBoolExpression(f['requiredWhen']));
    if (must && (v == null || v.isEmpty)) return 'Обовʼязкове поле';
    return null;
  }

  @override
  void dispose() {
    for (var c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
