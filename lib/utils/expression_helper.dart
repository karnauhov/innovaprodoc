import 'dart:math';

class ExpressionHelper {
  static bool isExpression(String s) => s.contains(r'${');

  static String compute(
    String template,
    Map<String, dynamic> values,
    Map<String, int> seqCounters,
  ) {
    final m = RegExp(r'\$\{(.*)\}').firstMatch(template);
    if (m == null) return template;
    final expr = m.group(1)!.trim();
    final parts = _splitPlus(expr);
    String out = '';
    for (var part in parts) {
      part = part.trim();
      if (part.startsWith("'") && part.endsWith("'")) {
        out += part.substring(1, part.length - 1);
      } else if (part.contains(RegExp(r'^\d+\$'))) {
        out += part;
      } else if (part.startsWith('year(')) {
        final inner = _innerOf(part, 'year');
        if (inner != null) {
          final val = _evalFunction(inner.trim(), values);
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
      } else if (part.startsWith('pad(')) {
        final inner = _innerOf(part, 'pad');
        if (inner != null) {
          final args = _splitArgs(inner);
          final n =
              int.tryParse(_evalFunctionOrValue(args[0], values).toString()) ??
              0;
          final len =
              int.tryParse(_evalFunctionOrValue(args[1], values).toString()) ??
              0;
          out += n.toString().padLeft(len, '0');
        }
      } else if (part.startsWith('seq(')) {
        final inner = _innerOf(part, 'seq');
        if (inner != null) {
          final name = inner.trim();
          final key = name.replaceAll("'", "").replaceAll('"', '');
          seqCounters[key] = (seqCounters[key] ?? 0) + 1;
          out += seqCounters[key].toString();
        }
      } else if (part.startsWith('now()') || part == 'now()') {
        out += DateTime.now().toIso8601String();
      } else if (part.startsWith('today()') || part == 'today()') {
        final d = DateTime.now();
        out += '${d.year}-${_two(d.month)}-${_two(d.day)}';
      } else if (part.startsWith('uuid()') || part == 'uuid()') {
        out += _genUuid();
      } else {
        final val = values[part];
        if (val != null) out += val.toString();
      }
    }
    return out;
  }

  static bool evaluateBoolExpression(
    String template,
    Map<String, dynamic> values, [
    Map<String, dynamic>? localScope,
  ]) {
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
        bool partRes = _evalComparison(trimmed, values, localScope);
        andRes = andRes && partRes;
      }
      if (andRes) return true;
    }
    return false;
  }

  // -------------------- private helpers -------------------------------
  static dynamic _evalFunction(String code, Map<String, dynamic> values) {
    code = code.trim();
    if (code == 'now()') return DateTime.now();
    if (code == 'today()') return DateTime.now().toIso8601String();
    if (code.startsWith('now(') || code.startsWith('today(')) {
      return DateTime.now();
    }
    if (code.startsWith("'") && code.endsWith("'")) {
      return code.substring(1, code.length - 1);
    }
    if (values.containsKey(code)) return values[code];
    return code;
  }

  static dynamic _evalFunctionOrValue(
    String token,
    Map<String, dynamic> values,
  ) {
    token = token.trim();
    if (token.startsWith("'") && token.endsWith("'")) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'now()') return DateTime.now();
    if (values.containsKey(token)) return values[token];
    return token;
  }

  static String? _innerOf(String s, String fn) {
    final re = RegExp(r'\\b' + RegExp.escape(fn) + r'\\((.*)\\)\$');
    final m = re.firstMatch(s);
    return m?.group(1);
  }

  static List<String> _splitPlus(String expr) {
    List<String> res = [];
    String cur = '';
    bool inQuote = false;
    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == "'" && (i == 0 || expr[i - 1] != '\\\\')) {
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

  static List<String> _splitArgs(String s) {
    List<String> res = [];
    String cur = '';
    bool inQuote = false;
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == "'" && (i == 0 || s[i - 1] != '\\\\')) {
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

  static List<String> _splitByTopLevel(String s, String delim) {
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

  static bool _evalComparison(
    String cmp,
    Map<String, dynamic> values,
    Map<String, dynamic>? localScope,
  ) {
    var s = cmp.trim();
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
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return v != null;
    }
  }

  static dynamic _resolveValue(
    String token,
    Map<String, dynamic> values,
    Map<String, dynamic>? localScope,
  ) {
    token = token.trim();
    if (token.startsWith("'") && token.endsWith("'")) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') return true;
    if (token == 'false') return false;
    if (token.startsWith('year(')) {
      final inner = _innerOf(token, 'year');
      if (inner != null) {
        final innerVal = _evalFunction(inner.trim(), values);
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

  static dynamic _parseLiteralOrValue(
    String token,
    Map<String, dynamic> values,
    Map<String, dynamic>? localScope,
  ) {
    token = token.trim();
    if (token.startsWith("'") && token.endsWith("'")) {
      return token.substring(1, token.length - 1);
    }
    if (token == 'true') return true;
    if (token == 'false') return false;
    return _resolveValue(token, values, localScope);
  }

  static String _two(int n) => n < 10 ? '0\$n' : '\$n';

  static String _genUuid() {
    final r = Random();
    return List<int>.generate(
      16,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
