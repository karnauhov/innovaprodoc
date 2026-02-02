// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:innovaprodoc/utils/expression_helper.dart';
import 'package:innovaprodoc/utils/storage_backend.dart';
import 'package:innovaprodoc/utils/timer_handle.dart';
import 'package:innovaprodoc/widgets/attachments_widget.dart';
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
  bool autosaveEnabled = true;
  int autosaveDebounceMs = 5000;
  String autosaveStorage = '';
  bool unsavedChangesGuard = false;
  bool hasUnsavedChanges = false;
  String? lastSavedSnapshot;
  String? storageKey;
  String? formId;
  Map<String, dynamic> enums = {};
  late Map<String, dynamic> schema;
  dynamic storage;
  bool _suppressFieldChanges = false;
  bool _isSending = false;
  final Set<String> _repeaterValidationErrors = <String>{};
  final Map<String, String> _repeaterErrorMessages = <String, String>{};

  @override
  void initState() {
    super.initState();
    storage = StorageBackend();
    schema = widget.schema;
    enums = Map<String, dynamic>.from(schema['enums'] ?? {});
    formId = schema['formId'] ?? "default_form";
    _initBehaviorSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSeqCounter();
      _createNewDocument();
    });
  }

  void _initBehaviorSettings() {
    final bs = schema['behavior']?['autosave'];
    if (bs is Map<String, dynamic>) {
      autosaveEnabled = bs['enabled'] == true;
      final dm = bs['debounceMs'];
      if (dm is int) {
        autosaveDebounceMs = dm;
      } else if (dm is String) {
        final parsed = int.tryParse(dm);
        if (parsed != null) {
          autosaveDebounceMs = parsed;
        }
      }
      final st = bs['storage'];
      if (st is String) {
        autosaveStorage = st;
      }
    }
    unsavedChangesGuard = schema['behavior']?['unsavedChangesGuard'] ?? false;
  }

  String _storageLabel() {
    if (autosaveStorage.isNotEmpty) {
      return autosaveStorage;
    }
    try {
      if (storage != null) {
        final usesLocal = storage.usesLocalStorage();
        return usesLocal ? 'local' : 'memory';
      }
    } catch (_) {}
    return 'unknown';
  }

  void _initSeqCounter() {
    final key = 'seq:${formId ?? 'default_form'}';
    if (!seqCounters.containsKey(key)) {
      try {
        final s = storage.getItem(key);
        if (s != null) {
          final parsed = int.tryParse(s);
          if (parsed != null) {
            seqCounters[key] = parsed;
            return;
          }
        }
        seqCounters[key] = 0;
      } catch (_) {
        seqCounters[key] = 0;
      }
    }
  }

  int _incrementDocumentCounter() {
    final key = 'seq:${formId ?? 'default_form'}';
    final current = seqCounters[key] ?? 0;
    final next = current + 1;
    seqCounters[key] = next;
    try {
      storage.setItem(key, next.toString());
    } catch (_) {}
    return next;
  }

  Future<void> _onCreateNewPressed() async {
    final proceed = await _checkUnsavedAndProceed();
    if (!proceed) return;
    _createNewDocument();
  }

  Future<void> _onOpenPressed() async {
    final proceed = await _checkUnsavedAndProceed();
    if (!proceed) return;
    _openPickDialog();
  }

  Future<bool> _checkUnsavedAndProceed() async {
    if (!unsavedChangesGuard) {
      return true;
    }
    if (!hasUnsavedChanges) {
      return true;
    }
    return await _confirmDiscardChanges();
  }

  Future<bool> _confirmDiscardChanges() async {
    final res = await showDialog<_UnsavedChoice>(
      barrierDismissible: false,
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Документ не збережено'),
          content: Text(
            'Поточний документ містить незбережені зміни. Що зробити?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _UnsavedChoice.cancel),
              child: Text('Скасувати'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, _UnsavedChoice.continueWithoutSave),
              child: Text('Продовжити без збереження'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, _UnsavedChoice.save),
              child: Text('Зберегти'),
            ),
          ],
        );
      },
    );

    if (res == null || res == _UnsavedChoice.cancel) {
      return false;
    } else if (res == _UnsavedChoice.continueWithoutSave) {
      return true;
    } else if (res == _UnsavedChoice.save) {
      final ok = _saveDraftToLocal();
      return ok;
    }
    return false;
  }

  void _createNewDocument() {
    _initSeqCounter();
    _incrementDocumentCounter();

    values.clear();
    for (var c in controllers.values) {
      c.dispose();
    }
    controllers.clear();
    repeaterData.clear();
    _repeaterValidationErrors.clear();
    _repeaterErrorMessages.clear();

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
      } else {
        values[k] = null;
      }
    });

    for (var s in (schema['sections'] as List<dynamic>? ?? [])) {
      final sec = s as Map<String, dynamic>;
      for (var f in (sec['fields'] as List<dynamic>? ?? [])) {
        final fm = f as Map<String, dynamic>;
        final key = fm['key'];
        if (fm['type'] != 'repeater') {
          controllers.putIfAbsent(key, () => TextEditingController(text: ''));
          if ((fm.containsKey('computed') || fm.containsKey('default')) &&
              (values[key] == null || values[key].toString().isEmpty)) {
            if (fm.containsKey('computed')) {
              final comp = fm['computed'];
              if (comp is String && ExpressionHelper.isExpression(comp)) {
                final computed = ExpressionHelper.compute(
                  comp,
                  values,
                  seqCounters,
                );
                values[key] = computed;
                controllers[key]!.text = computed.toString();
              }
            } else if (fm.containsKey('default')) {
              final d = fm['default'];
              if (d is String && ExpressionHelper.isExpression(d)) {
                final computed = ExpressionHelper.compute(
                  d,
                  values,
                  seqCounters,
                );
                values[key] = computed;
                controllers[key]!.text = computed.toString();
              } else if (d != null) {
                values[key] = d;
                controllers[key]!.text = d.toString();
              }
            }
          } else {
            controllers[key]!.text = values[key]?.toString() ?? '';
          }
        } else {
          repeaterData[key] = [];
        }
      }
    }

    _computeStorageKey();
    _saveDraftToLocal();
    widget.onStatus('Новий документ створено і збережено (${_storageLabel()})');
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _formKey.currentState?.reset();
      } catch (_) {}
    });
  }

  void _computeStorageKey() {
    final bs = schema['behavior']?['autosave'] ?? {};
    final templ = bs['storageKeyTemplate'] ?? '';
    if (templ is String && templ.contains('\${')) {
      try {
        storageKey = templ.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (m) {
          final expr = m.group(1)!;
          return ExpressionHelper.compute('\${$expr}', values, seqCounters);
        });
      } catch (_) {
        storageKey = templ.toString();
      }
    } else {
      storageKey = templ.toString();
    }
  }

  List<String> _storageKeys() {
    try {
      if (storage != null) {
        final dyn = storage;
        try {
          final keys = dyn.keys();
          if (keys is List<String>) {
            return keys;
          }
          if (keys is Iterable) {
            return keys.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
    } catch (_) {}
    try {
      return html.window.localStorage.keys.toList();
    } catch (_) {}
    return <String>[];
  }

  List<Map<String, String>> _gatherSavedDocuments() {
    final res = <Map<String, String>>[];
    final keys = _storageKeys();
    for (var k in keys) {
      try {
        final s = storage.getItem(k);
        if (s == null) {
          continue;
        }
        final map = json.decode(s) as Map<String, dynamic>;
        final number = map['number']?.toString() ?? '';
        final title = map['title']?.toString() ?? '';
        final status = map['status']?.toString() ?? '';
        res.add({'key': k, 'number': number, 'title': title, 'status': status});
      } catch (_) {
        continue;
      }
    }
    return res;
  }

  Future<void> _openPickDialog() async {
    final docs = _gatherSavedDocuments();
    String? selectedKey;
    await showDialog(
      context: context,
      builder: (ctx) {
        final items = docs.map((d) {
          final label =
              (d['number']?.isNotEmpty == true ? '[${d['number']}] ' : '') +
              (d['title']?.isNotEmpty == true ? d['title']! : d['key']!);
          return DropdownMenuItem<String>(
            value: d['key'],
            child: Text(
              label,
              style: TextStyle(
                color: d['status'] == "SUBMITTED" ? Colors.green : Colors.red,
              ),
            ),
          );
        }).toList();
        if (items.isEmpty) {
          return AlertDialog(
            title: Text('Відкрити документ'),
            content: Text('Документів у сховищі не знайдено'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Закрити'),
              ),
            ],
          );
        }
        selectedKey = docs.first['key'];
        return AlertDialog(
          title: Text('Відкрити документ'),
          content: StatefulBuilder(
            builder: (c, setS) {
              return DropdownButton<String>(
                value: selectedKey,
                items: items,
                onChanged: (v) {
                  setS(() {
                    selectedKey = v;
                  });
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Скасувати'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (selectedKey != null) {
                  _loadDocumentByKey(selectedKey!);
                }
              },
              child: Text('Завантажити'),
            ),
          ],
        );
      },
    );
  }

  void _loadDocumentByKey(String key) {
    try {
      _suppressFieldChanges = true;
      autosaveTimer?.cancel();

      final s = storage.getItem(key);
      if (s == null) {
        widget.onStatus('Документ не знайдено за ключем $key');
        _suppressFieldChanges = false;
        return;
      }

      _repeaterValidationErrors.clear();
      _repeaterErrorMessages.clear();

      final map = json.decode(s) as Map<String, dynamic>;
      final Map<String, String> fieldTypes = {};
      for (var sec in (schema['sections'] as List<dynamic>? ?? [])) {
        final secMap = sec as Map<String, dynamic>;
        for (var f in (secMap['fields'] as List<dynamic>? ?? [])) {
          final fm = f as Map<String, dynamic>;
          final k = fm['key'] as String;
          final t = (fm['type'] as String?) ?? 'text';
          fieldTypes[k] = t;
        }
      }
      for (var dmKey
          in ((schema['dataModel'] as Map<String, dynamic>?) ?? {}).keys) {
        if (!fieldTypes.containsKey(dmKey)) {
          fieldTypes[dmKey] = 'text';
        }
      }

      dynamic defaultForType(String t) {
        switch (t) {
          case 'multiline':
          case 'text':
          case 'date':
          case 'number':
          case 'computed':
            return '';
          case 'select':
            return null;
          case 'money':
            return null;
          case 'bool':
            return false;
          case 'attachments':
            return <String>[];
          case 'repeater':
            return <Map<String, dynamic>>[];
          default:
            return null;
        }
      }

      fieldTypes.forEach((k, t) {
        if (t == 'repeater') {
          repeaterData[k] = <Map<String, dynamic>>[];
        } else {
          values[k] = defaultForType(t);
        }
        if (controllers.containsKey(k)) {
          final val = values[k];
          controllers[k]!.text = (val == null) ? '' : val.toString();
        }
      });

      map.forEach((k, v) {
        if (repeaterData.containsKey(k) && v is List) {
          repeaterData[k] = v.map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          values[k] = v;
          if (controllers.containsKey(k)) {
            controllers[k]!.text = v?.toString() ?? '';
          }
        }
      });

      storageKey = key;
      lastSavedSnapshot = s;
      hasUnsavedChanges = false;
      widget.onStatus(
        'Документ (${values["title"] != null && values["title"] != "" ? values["title"] : values["docId"]}) завантажено',
      );

      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _formKey.currentState?.reset();
        } catch (_) {}
        Future.microtask(() {
          _suppressFieldChanges = false;
        });
      });
    } catch (err) {
      widget.onStatus('Помилка при завантаженні: $err');
      _suppressFieldChanges = false;
    }
  }

  void onFieldChanged(String key, dynamic value) {
    values[key] = value;
    if (_repeaterValidationErrors.contains(key)) {
      _repeaterValidationErrors.remove(key);
      _repeaterErrorMessages.remove(key);
    }

    if (_suppressFieldChanges) {
      _recomputeComputedFields();
      if (controllers.containsKey(key)) {
        controllers[key]!.text = value?.toString() ?? '';
      }
      setState(() {});
      return;
    }

    _recomputeComputedFields();
    hasUnsavedChanges = true;
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
            if (key == 'number' &&
                values[key] != null &&
                values[key].toString().isNotEmpty) {
              continue;
            }
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

  bool _saveDraftToLocal({bool skipStatus = false}) {
    if (storageKey == null || storageKey!.isEmpty) {
      widget.onStatus('Немає ключа сховища для збереження');
      return false;
    }

    try {
      final actions = (schema['actions'] as List<dynamic>?) ?? <dynamic>[];
      Map<String, dynamic>? saveAction;
      for (var a in actions) {
        try {
          final am = a as Map<String, dynamic>;
          if (am['id'] == 'saveDraft' || am['type'] == 'localSave') {
            saveAction = am;
            break;
          }
        } catch (_) {
          continue;
        }
      }

      if (saveAction != null) {
        final payload = (saveAction['payload'] as Map<String, dynamic>?) ?? {};
        payload.forEach((pKey, pVal) {
          if (!skipStatus || pKey != "status") {
            if (pVal is String && ExpressionHelper.isExpression(pVal)) {
              final computed = ExpressionHelper.compute(
                pVal,
                values,
                seqCounters,
              );
              values[pKey] = computed;
              if (controllers.containsKey(pKey)) {
                controllers[pKey]!.text = computed.toString();
              }
            } else {
              values[pKey] = pVal;
              if (controllers.containsKey(pKey)) {
                controllers[pKey]!.text = pVal?.toString() ?? '';
              }
            }
          }
        });
      }
    } catch (_) {}

    final snapshot = <String, dynamic>{};
    snapshot.addAll(values);
    repeaterData.forEach((k, list) {
      snapshot[k] = list;
    });
    try {
      final encoded = json.encode(snapshot);
      storage.setItem(storageKey!, encoded);
      lastSavedSnapshot = encoded;
      hasUnsavedChanges = false;
      widget.onStatus('Чернетка збережена (${_storageLabel()})');
      setState(() {});
      return true;
    } catch (_) {
      widget.onStatus('Не вдалося зберегти');
      return false;
    }
  }

  bool _validateForm() {
    final formState = _formKey.currentState;
    if (formState == null) {
      return false;
    }
    final ok = formState.validate();
    _repeaterValidationErrors.clear();
    _repeaterErrorMessages.clear();

    for (var s in (schema['sections'] as List<dynamic>? ?? [])) {
      final sec = s as Map<String, dynamic>;
      for (var f in (sec['fields'] as List<dynamic>? ?? [])) {
        final fm = f as Map<String, dynamic>;
        if (fm['type'] == 'repeater') {
          final key = fm['key'] as String;
          final minItemsConds = (fm['minItemsWhen'] as List<dynamic>?) ?? [];
          for (var cond in minItemsConds) {
            final when = cond['when'];
            final min = cond['min'] ?? 0;
            if (when != null &&
                ExpressionHelper.evaluateBoolExpression(when, values)) {
              final count = repeaterData[key]?.length ?? 0;
              if (count < min) {
                final message = 'Потрібно додати мінімум $min елементів';
                widget.onStatus(message);
                _repeaterValidationErrors.add(key);
                _repeaterErrorMessages[key] = message;
              }
            }
          }
        }
      }
    }
    setState(() {});
    final repeaterOk = _repeaterValidationErrors.isEmpty;
    return ok && repeaterOk;
  }

  Map<String, dynamic> _buildDocumentSnapshot() {
    final snap = <String, dynamic>{};
    snap.addAll(values);
    repeaterData.forEach((k, list) {
      snap[k] = list;
    });
    return snap;
  }

  Future<bool> _simulateSend(
    Map<String, dynamic> document, {
    int delayMs = 1000,
    bool shouldFail = false,
  }) async {
    await Future.delayed(Duration(milliseconds: delayMs));
    return !shouldFail;
  }

  Future<void> _handleSubmitAction() async {
    if (_isSending) return;
    final actions = (schema['actions'] as List<dynamic>?) ?? <dynamic>[];
    Map<String, dynamic>? submitAction;
    for (var a in actions) {
      try {
        final am = a as Map<String, dynamic>;
        if ((am['type'] == 'submit') || (am['id'] == 'submit')) {
          submitAction = am;
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (submitAction == null) {
      if (!_validateForm()) {
        widget.onStatus('Виправте помилки у формі');
        return;
      }
      values['status'] = 'SUBMITTED';
      widget.onStatus('Submitted');
      _saveDraftToLocal(skipStatus: true);
      return;
    }

    final preconds = (submitAction['preconditions'] as List<dynamic>?) ?? [];
    for (var p in preconds) {
      try {
        final pm = p as Map<String, dynamic>;
        final rule = pm['rule']?.toString();
        final message = pm['message']?.toString() ?? 'Precondition failed';
        if (rule == 'validateForm') {
          final ok = _validateForm();
          if (!ok) {
            widget.onStatus(message);
            return;
          }
        }
      } catch (_) {
        continue;
      }
    }

    final docSnapshot = _buildDocumentSnapshot();
    setState(() {
      _isSending = true;
    });

    bool success = false;
    try {
      success = await _simulateSend(
        docSnapshot,
        delayMs: 1000,
        shouldFail: false,
      );
    } catch (_) {
      success = false;
    }

    if (success) {
      try {
        final onSuccess =
            (submitAction['onSuccess'] as Map<String, dynamic>?) ?? {};
        final setMap = (onSuccess['set'] as Map<String, dynamic>?) ?? {};
        _suppressFieldChanges = true;
        setMap.forEach((k, v) {
          if (v is String && ExpressionHelper.isExpression(v)) {
            try {
              final computed = ExpressionHelper.compute(v, values, seqCounters);
              values[k] = computed;
              if (controllers.containsKey(k)) {
                controllers[k]!.text = computed.toString();
              }
            } catch (_) {
              values[k] = v;
              if (controllers.containsKey(k)) {
                controllers[k]!.text = v.toString();
              }
            }
          } else {
            values[k] = v;
            if (controllers.containsKey(k)) {
              controllers[k]!.text = v?.toString() ?? '';
            }
          }
        });
        _saveDraftToLocal(skipStatus: true);

        final toast = onSuccess['toast']?.toString() ?? 'Submitted';
        widget.onStatus(toast);
      } catch (err) {
        widget.onStatus('Помилка при обробці успіху: $err');
      } finally {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _suppressFieldChanges = false;
          setState(() {
            _isSending = false;
            hasUnsavedChanges = false;
          });
        });
      }
    } else {
      final onFailure =
          (submitAction['onFailure'] as Map<String, dynamic>?) ?? {};
      final toast = onFailure['toast']?.toString() ?? 'Failed to submit';
      widget.onStatus(toast);
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  void dispose() {
    for (var c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = (schema['sections'] as List<dynamic>? ?? []);
    final actions = (schema['actions'] as List<dynamic>? ?? []);
    final localSaveAction = actions.firstWhere((t) => t["type"] == "localSave");
    final submitAction = actions.firstWhere((t) => t["type"] == "submit");
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 12.0,
            ),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await _onCreateNewPressed();
                  },
                  icon: Icon(Icons.post_add),
                  label: Text('Створити новий'),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await _onOpenPressed();
                  },
                  icon: Icon(Icons.folder_open),
                  label: Text('Відкрити'),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    _saveDraftToLocal();
                  },
                  icon: Icon(Icons.save),
                  label: Text(localSaveAction["label"] ?? 'Зберегти'),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    _handleSubmitAction();
                  },
                  icon: _isSending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send),
                  label: Text(submitAction["label"] ?? 'Відправити'),
                ),
                Spacer(),
                Tooltip(
                  message: hasUnsavedChanges
                      ? 'Є незбережені зміни'
                      : 'Все збережено',
                  child: hasUnsavedChanges
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Colors.green,
                        ),
                ),
              ],
            ),
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
    if (!visible) {
      return SizedBox();
    }

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
                final isoDate = iso.split('T').first;
                controllers[key]!.text = isoDate;
                onFieldChanged(key, isoDate);
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
          onStatus: widget.onStatus,
        );

      case 'repeater':
        final hasError = _repeaterValidationErrors.contains(key);
        final errorMessage = _repeaterErrorMessages[key];
        final repeaterWidget = RepeaterWidget(
          keyName: key,
          field: f,
          repeaterData: repeaterData,
          controllers: controllers,
          enums: enums,
          onChanged: (items) => onFieldChanged(key, items),
        );

        if (!hasError) {
          return repeaterWidget;
        }

        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: repeaterWidget,
              ),
              if (errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 6),
                  child: Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
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
            ExpressionHelper.evaluateBoolExpression(f['requiredWhen'], values));
    if (must && (v == null || v.isEmpty)) {
      return 'Обов\'язкове поле';
    }
    return null;
  }
}

enum _UnsavedChoice { cancel, continueWithoutSave, save }
