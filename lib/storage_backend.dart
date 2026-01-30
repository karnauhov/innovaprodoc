import 'package:web/web.dart' as web;

class StorageBackend {
  final Map<String, String> _mem = {};
  bool available = false;

  StorageBackend() {
    try {
      // test access
      //final ls = web.window.localStorage;
      //ls.add() ['__storage_test__'] = '1';
      //ls.remove('__storage_test__');
      available = true;
    } catch (e) {
      available = false;
    }
  }

  String? getItem(String key) {
    if (available) {
      try {
        // ignore: deprecated_member_use
        return web.window.localStorage[key];
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
        // ignore: deprecated_member_use
        web.window.localStorage[key] = value;
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
        //web.window.localStorage.remove(key);
        return;
      } catch (e) {
        available = false;
      }
    }
    _mem.remove(key);
  }

  bool usesLocalStorage() => available;
}
