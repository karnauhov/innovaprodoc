import 'package:web/web.dart' as web;

class StorageBackend {
  final Map<String, String> _mem = {};
  bool available = false;

  StorageBackend() {
    try {
      final ls = web.window.localStorage;
      ls.setItem('__storage_test__', '1');
      ls.removeItem('__storage_test__');
      available = true;
    } catch (e) {
      available = false;
    }
  }

  String? getItem(String key) {
    if (available) {
      try {
        return web.window.localStorage.getItem(key);
      } catch (e) {
        available = false;
        return _mem[key];
      }
    } else {
      return _mem[key];
    }
  }

  void setItem(String key, String value) {
    if (available) {
      try {
        web.window.localStorage.setItem(key, value);
        return;
      } catch (e) {
        available = false;
      }
    }
    _mem[key] = value;
  }

  void removeItem(String key) {
    if (available) {
      try {
        web.window.localStorage.removeItem(key);
        return;
      } catch (e) {
        available = false;
      }
    }
    _mem.remove(key);
  }

  bool usesLocalStorage() => available;
}
