import 'package:uuid/uuid.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class ExpressionHelper {
  static final Uuid _uuid = Uuid();

  static bool isExpression(String s) => s.contains(r'${');

  static String compute(
    String template,
    Map<String, dynamic> values,
    Map<String, int> seqCounters,
  ) {
    final m = RegExp(r'\$\{(.+)\}').firstMatch(template);
    if (m == null) {
      return template;
    }
    final expr = m.group(1)!.trim();
    final parts = _splitPlus(expr);
    final sb = StringBuffer();
    for (var part in parts) {
      part = part.trim();
      final val = _evaluateToken(part, values, seqCounters, raw: false);
      if (val != null) {
        sb.write(val.toString());
      }
    }
    return sb.toString();
  }

  static bool evaluateBoolExpression(
    String template,
    Map<String, dynamic> values, [
    Map<String, dynamic>? localScope,
  ]) {
    final m = RegExp(r'\$\{(.*)\}').firstMatch(template);
    if (m == null) {
      return false;
    }
    String expr = m.group(1)!;
    expr = expr.trim();
    final ors = _splitByTopLevel(expr, '||');
    for (var orPart in ors) {
      final andParts = _splitByTopLevel(orPart, '&&');
      var andRes = true;
      for (var ap in andParts) {
        final trimmed = ap.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (!_evalComparison(trimmed, values, localScope)) {
          andRes = false;
          break;
        }
      }
      if (andRes) {
        return true;
      }
    }
    return false;
  }

  // core evaluator; raw=true returns typed values
  static dynamic _evaluateToken(
    String token,
    Map<String, dynamic> values,
    Map<String, int> seqCounters, {
    bool raw = true,
  }) {
    token = token.trim();
    if (token.isEmpty) {
      return raw ? null : '';
    }

    if (_isQuoted(token)) {
      return token.substring(1, token.length - 1);
    }

    if (RegExp(r'^\d+$').hasMatch(token)) {
      final n = int.tryParse(token);
      return raw ? n : n.toString();
    }

    final fnMatch = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*\(').firstMatch(token);
    if (fnMatch != null) {
      final fn = fnMatch.group(1)!;
      final inner = _innerOf(token, fn) ?? '';
      final args = inner.trim().isEmpty ? <String>[] : _splitArgs(inner);
      final evaluatedArgs = args
          .map((a) => _evaluateToken(a, values, seqCounters, raw: true))
          .toList();

      switch (fn) {
        case 'seq':
          final rawName = evaluatedArgs.isNotEmpty ? evaluatedArgs[0] : null;
          final name = rawName is String ? rawName : rawName?.toString() ?? '';
          final seq = _getSeqForFormAware(name, seqCounters);
          return raw ? seq : seq.toString();

        case 'pad':
          final rawVal = evaluatedArgs.isNotEmpty ? evaluatedArgs[0] : 0;
          final rawLen = evaluatedArgs.length > 1 ? evaluatedArgs[1] : 0;
          final valNum = _toIntSafe(rawVal);
          final lenNum = _toIntSafe(rawLen);
          final padded = valNum.toString().padLeft(lenNum, '0');
          return raw ? padded : padded.toString();

        case 'year':
          final innerVal = evaluatedArgs.isNotEmpty ? evaluatedArgs[0] : null;
          DateTime? dt;
          if (innerVal is DateTime) {
            dt = innerVal;
          } else if (innerVal is String) {
            dt = _tryParseDate(innerVal);
          } else {
            dt = null;
          }
          final year = dt?.year ?? DateTime.now().year;
          return raw ? year : year.toString();

        case 'now':
          final now = DateTime.now();
          return raw ? now : now.toIso8601String();

        case 'today':
          final today = DateTime.now();
          if (raw) {
            return today;
          } else {
            return '${today.year}-${_two(today.month)}-${_two(today.day)}';
          }

        case 'uuid':
          final id = _uuid.v4();
          return id;

        default:
          return raw ? token : token;
      }
    }

    if (values.containsKey(token)) {
      final v = values[token];
      if (!raw) {
        return v?.toString() ?? '';
      }
      return v;
    }

    return raw ? token : token;
  }

  static int _getSeqForFormAware(String name, Map<String, int> seqCounters) {
    final formKey = seqCounters.keys.firstWhere(
      (k) => k.startsWith('seq:'),
      orElse: () => '',
    );
    if (formKey.isNotEmpty) {
      final current = seqCounters[formKey] ?? 0;
      if (current > 0) {
        return current;
      } else {
        try {
          final ls = html.window.localStorage;
          final stored = ls[formKey];
          final parsed = stored != null ? (int.tryParse(stored) ?? 0) : 0;
          final next = parsed + 1;
          ls[formKey] = next.toString();
          seqCounters[formKey] = next;
          return next;
        } catch (_) {
          final next = (seqCounters[formKey] ?? 0) + 1;
          seqCounters[formKey] = next;
          return next;
        }
      }
    }

    final key = 'seq:$name';
    if (seqCounters.containsKey(key)) {
      seqCounters[key] = seqCounters[key]! + 1;
      return seqCounters[key]!;
    }
    try {
      final ls = html.window.localStorage;
      final cur = ls[key];
      if (cur != null) {
        final parsed = int.tryParse(cur) ?? 0;
        final next = parsed + 1;
        ls[key] = next.toString();
        seqCounters[key] = next;
        return next;
      } else {
        ls[key] = '1';
        seqCounters[key] = 1;
        return 1;
      }
    } catch (_) {
      seqCounters[key] = (seqCounters[key] ?? 0) + 1;
      return seqCounters[key]!;
    }
  }

  static bool _isQuoted(String s) {
    if (s.length < 2) {
      return false;
    }
    return (s.startsWith("'") && s.endsWith("'")) ||
        (s.startsWith('"') && s.endsWith('"'));
  }

  static int _toIntSafe(dynamic v) {
    if (v is int) {
      return v;
    } else if (v is String) {
      return int.tryParse(v) ?? 0;
    } else {
      return 0;
    }
  }

  static DateTime? _tryParseDate(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  static bool _isEscaped(String s, int i) {
    var back = i - 1;
    var escaped = false;
    while (back >= 0 && s[back] == '\\') {
      escaped = !escaped;
      back--;
    }
    return escaped;
  }

  static List<String> _splitPlus(String expr) {
    final res = <String>[];
    final cur = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var depth = 0;
    for (var i = 0; i < expr.length; i++) {
      final ch = expr[i];
      final escaped = _isEscaped(expr, i);
      if (!escaped && ch == "'" && !inDouble) {
        inSingle = !inSingle;
        cur.write(ch);
        continue;
      }
      if (!escaped && ch == '"' && !inSingle) {
        inDouble = !inDouble;
        cur.write(ch);
        continue;
      }
      if (inSingle || inDouble) {
        cur.write(ch);
        continue;
      }
      if (ch == '(') {
        depth++;
        cur.write(ch);
        continue;
      }
      if (ch == ')') {
        depth = depth > 0 ? depth - 1 : 0;
        cur.write(ch);
        continue;
      }
      if (ch == '+' && depth == 0) {
        res.add(cur.toString());
        cur.clear();
        continue;
      }
      cur.write(ch);
    }
    if (cur.isNotEmpty) {
      res.add(cur.toString());
    }
    return res;
  }

  static List<String> _splitArgs(String s) {
    final res = <String>[];
    final cur = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final escaped = _isEscaped(s, i);
      if (!escaped && ch == "'" && !inDouble) {
        inSingle = !inSingle;
        cur.write(ch);
        continue;
      }
      if (!escaped && ch == '"' && !inSingle) {
        inDouble = !inDouble;
        cur.write(ch);
        continue;
      }
      if (inSingle || inDouble) {
        cur.write(ch);
        continue;
      }
      if (ch == '(') {
        depth++;
        cur.write(ch);
        continue;
      }
      if (ch == ')') {
        depth = depth > 0 ? depth - 1 : 0;
        cur.write(ch);
        continue;
      }
      if (ch == ',' && depth == 0) {
        res.add(cur.toString().trim());
        cur.clear();
        continue;
      }
      cur.write(ch);
    }
    if (cur.toString().trim().isNotEmpty) {
      res.add(cur.toString().trim());
    }
    return res;
  }

  static String? _innerOf(String s, String fn) {
    final startIdx = s.indexOf('$fn(');
    if (startIdx == -1) {
      return null;
    }
    final openIdx = s.indexOf('(', startIdx + fn.length);
    if (openIdx == -1 || openIdx + 1 >= s.length) {
      return null;
    }
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    final buf = StringBuffer();
    for (var i = openIdx + 1; i < s.length; i++) {
      final ch = s[i];
      final escaped = _isEscaped(s, i);
      if (!escaped && ch == "'" && !inDouble) {
        inSingle = !inSingle;
        buf.write(ch);
        continue;
      }
      if (!escaped && ch == '"' && !inSingle) {
        inDouble = !inDouble;
        buf.write(ch);
        continue;
      }
      if (inSingle || inDouble) {
        buf.write(ch);
        continue;
      }
      if (ch == '(') {
        depth++;
        buf.write(ch);
        continue;
      }
      if (ch == ')') {
        if (depth == 0) {
          return buf.toString();
        } else {
          depth--;
          buf.write(ch);
          continue;
        }
      }
      buf.write(ch);
    }
    return null;
  }

  static List<String> _splitByTopLevel(String s, String delim) {
    final res = <String>[];
    var idx = 0;
    var last = 0;
    var depth = 0;
    var inSingle = false;
    var inDouble = false;
    while (idx < s.length) {
      if (!inSingle && !inDouble && depth == 0 && s.startsWith(delim, idx)) {
        res.add(s.substring(last, idx));
        idx += delim.length;
        last = idx;
        continue;
      }
      final ch = s[idx];
      if (ch == "'" && (idx == 0 || s[idx - 1] != '\\') && !inDouble) {
        inSingle = !inSingle;
        idx++;
        continue;
      }
      if (ch == '"' && (idx == 0 || s[idx - 1] != '\\') && !inSingle) {
        inDouble = !inDouble;
        idx++;
        continue;
      }
      if (!inSingle && !inDouble) {
        if (ch == '(') {
          depth++;
        } else if (ch == ')') {
          depth = depth > 0 ? depth - 1 : 0;
        }
      }
      idx++;
    }
    res.add(s.substring(last));
    return res;
  }

  static bool _evalComparison(
    String cmp,
    Map<String, dynamic> values,
    Map<String, dynamic>? localScope,
  ) {
    final s = cmp.trim();
    if (s.contains('==')) {
      final parts = s.split('==');
      final l = parts[0].trim();
      final r = parts.sublist(1).join('==').trim();
      final lv = _resolveValue(l, values, localScope);
      final rv = _parseLiteralOrValue(r, values, localScope);
      return (lv?.toString() ?? '') == (rv?.toString() ?? '');
    } else if (s.contains('!=')) {
      final parts = s.split('!=');
      final l = parts[0].trim();
      final r = parts.sublist(1).join('!=').trim();
      final lv = _resolveValue(l, values, localScope);
      final rv = _parseLiteralOrValue(r, values, localScope);
      return (lv?.toString() ?? '') != (rv?.toString() ?? '');
    } else {
      final v = _resolveValue(s, values, localScope);
      if (v is bool) {
        return v;
      }
      if (v is String) {
        return v.toLowerCase() == 'true';
      }
      return v != null;
    }
  }

  static dynamic _resolveValue(
    String token,
    Map<String, dynamic> values,
    Map<String, dynamic>? localScope,
  ) {
    token = token.trim();
    if (_isQuoted(token)) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') {
      return true;
    }
    if (token == 'false') {
      return false;
    }
    if (localScope != null && localScope.containsKey(token)) {
      return localScope[token];
    }
    return values[token];
  }

  static dynamic _parseLiteralOrValue(
    String token,
    Map<String, dynamic> values,
    Map<String, dynamic>? localScope,
  ) {
    token = token.trim();
    if (_isQuoted(token)) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') {
      return true;
    }
    if (token == 'false') {
      return false;
    }
    return _resolveValue(token, values, localScope);
  }

  static String _two(int n) {
    return n < 10 ? '0$n' : '$n';
  }
}
