import 'package:shared_preferences/shared_preferences.dart';

/// Persistenz des kompletten App-Zustands als EIN JSON-Dokument.
///
/// Verwendet `shared_preferences` (Web → localStorage/IndexedDB-Backing des
/// Plugins, Android → SharedPreferences). Kein drift, kein sqflite, kein
/// Codegen.
class StorageService {
  const StorageService();

  static const String storageKey = 'tri_log_state_v1';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(storageKey);
  }

  Future<void> write(String document) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, document);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
