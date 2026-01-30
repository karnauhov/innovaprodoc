// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:innovaprodoc/utils/expression_helper.dart';
import 'package:innovaprodoc/utils/storage_backend.dart';
import 'package:innovaprodoc/utils/timer_handle.dart';
import 'package:innovaprodoc/widgets/action_buttons_row.dart';
import 'package:innovaprodoc/widgets/attachments_widget.dart';
import 'package:innovaprodoc/widgets/form_header_bar.dart';
import 'package:innovaprodoc/widgets/repeater_widget.dart';
import 'package:innovaprodoc/widgets/section_card.dart';

class DynamicForm extends StatefulWidget {
  final Map<String, dynamic> schema;
  final void Function(String) onStatus;
  const DynamicForm({super.key, required this.schema, required this.onStatus});

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
  late Map<String, dynamic> schema;
  late StorageBackend storage;

  @override
  void initState() {
    super.initState();
    storage = StorageBackend();
    schema = widget.schema;
    enums = Map<String, dynamic>.from(schema['enums'] ?? {});
    _initDataModel();
  }

  // ---------------------- data & expression helpers -----------------------
  void _initDataModel() {
    final dataModel = schema['dataModel'] ?? {};
    dataModel.forEach((k, def) {
      final defMap = def is Map ? def : {};
      if (defMap.containsKey('default')) {
        final defaultExpr = defMap['default'];
        if (defaultExpr is String &&
            ExpressionHelper.isExpression(defaultExpr)) {
          values[k] = ExpressionHelper.compute(
            defaultExpr,
            values,
            seqCounters,
          );
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
            if (comp is String && ExpressionHelper.isExpression(comp)) {
              controllers[key]!.text = ExpressionHelper.compute(
                comp,
                values,
                seqCounters,
              );
              values[key] = controllers[key]!.text;
            }
          } else if (fm.containsKey('default')) {
            final d = fm['default'];
            if (d is String && ExpressionHelper.isExpression(d)) {
              controllers[key]!.text = ExpressionHelper.compute(
                d,
                values,
                seqCounters,
              );
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
      storageKey = templ.replaceAllMapped(RegExp(r'\\${([^}]+)\\}'), (m) {
        final expr = m.group(1)!;
        return ExpressionHelper.compute('\${$expr}', values, seqCounters);
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
      if (d is String && ExpressionHelper.isExpression(d)) {
        return ExpressionHelper.compute(d, values, seqCounters);
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
            widget.onStatus(
              storage.usesLocalStorage()
                  ? "Чернетка відновлена зі сховища"
                  : "Чернетка відновлена із пам'яті",
            );
            setState(() {});
          });
        }
      } catch (e) {
        // ignore
      }
    }
  }

  // ---------------------- change / autosave / compute ---------------------
  void onFieldChanged(String key, dynamic value) {
    values[key] = value;
    // TODO FIX
    // if (controllers.containsKey(key)) {
    //   controllers[key]!.text = value?.toString() ?? '';
    // }
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
          if (comp is String && ExpressionHelper.isExpression(comp)) {
            final val = ExpressionHelper.compute(comp, values, seqCounters);
            values[key] = val;
            if (controllers.containsKey(key)) {
              controllers[key]!.text = val.toString();
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
      widget.onStatus(
        storage.usesLocalStorage()
            ? "Чернетка збережена у сховище"
            : "Чернетка збережена у пам'ять",
      );
    } catch (_) {}
  }

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
    final a = html.AnchorElement(href: url)..setAttribute('download', filename);
    // Clicking the anchor may be restricted in some sandboxed frames; still create the link.
    a.click();
    html.Url.revokeObjectUrl(url);
    widget.onStatus('Експортовано чернетку у файл $filename');
  }

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
            widget.onStatus('Імпортовано чернетку з файлу');
          } catch (err) {
            widget.onStatus('Помилка парсингу файлу: $err');
          }
        } else {
          widget.onStatus('Не вдалося прочитати файл як текст');
        }
      });
      reader.onError.first.then((err) {
        widget.onStatus('Помилка читання файлу: $err');
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
            if (when != null &&
                ExpressionHelper.evaluateBoolExpression(when, values)) {
              final count = repeaterData[key]?.length ?? 0;
              if (count < min) {
                widget.onStatus(
                  'Потрібно додати мінімум $min елементів у $key',
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
  void dispose() {
    for (var c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ----------------------------- build UI --------------------------------
  @override
  Widget build(BuildContext context) {
    final sections = (schema['sections'] as List<dynamic>? ?? []);
    final actions = (schema['actions'] as List<dynamic>? ?? []);
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          FormHeaderBar(
            title: schema['title'] ?? 'Form',
            usesLocalStorage: storage.usesLocalStorage(),
            onSaveDraft: _saveDraftToLocal,
            onExport: _exportDraftToFile,
            onImport: _importDraftFromFile,
          ),
          ...sections.map(
            (s) => SectionCard(
              section: s as Map<String, dynamic>,
              enums: enums,
              controllers: controllers,
              values: values,
              repeaterData: repeaterData,
              onFieldChanged: onFieldChanged,
              buildField: _buildField,
            ),
          ),
          SizedBox(height: 20),
          ActionButtonsRow(
            actions: actions,
            onSaveDraft: _saveDraftToLocal,
            onValidateAndSubmit: () {
              if (!_validateForm()) {
                widget.onStatus('Виправте помилки у формі');
                return;
              }
              values['status'] = 'SUBMITTED';
              final submit = (actions).firstWhere(
                (a) => a['type'] == 'submit',
                orElse: () => null,
              );
              final toast = submit != null
                  ? (submit['onSuccess']?['toast'])
                  : 'Submitted';
              widget.onStatus(toast);
              _saveDraftToLocal();
            },
          ),
          SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              'Current model (debug):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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

  Widget _buildField(Map<String, dynamic> f) {
    final key = f['key'] as String;
    final type = f['type'] as String? ?? 'text';
    final label = f['label'] ?? key;
    final readOnly = f['readOnly'] == true;
    final visibleWhen = f['visibleWhen'];
    final visible = visibleWhen == null
        ? true
        : ExpressionHelper.evaluateBoolExpression(visibleWhen, values);
    final required = f['required'] == true;
    final requiredWhen = f['requiredWhen'];
    final mustBeRequired = requiredWhen == null
        ? required
        : ExpressionHelper.evaluateBoolExpression(requiredWhen, values);
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
                return 'Обов\'язкове поле';
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
            onChanged: (v) => onFieldChanged(key, v),
          ),
        );

      case 'attachments':
        return AttachmentsWidget(
          keyName: key,
          field: f,
          values: values,
          onChanged: (list) => onFieldChanged(key, list),
        );

      case 'repeater':
        return RepeaterWidget(
          keyName: key,
          field: f,
          repeaterData: repeaterData,
          controllers: controllers,
          enums: enums,
          onChanged: (items) => onFieldChanged(key, items),
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
            ExpressionHelper.evaluateBoolExpression(f['requiredWhen'], values));
    if (must && (v == null || v.isEmpty)) return 'Обов\'язкове поле';
    return null;
  }
}
