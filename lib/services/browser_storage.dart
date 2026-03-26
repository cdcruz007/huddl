import 'package:shared_preferences/shared_preferences.dart';

/// Cross-platform persistent storage wrapper using shared_preferences
class BrowserStorage {
  static const String _prefix = 'flutter.';

  /// Save data to storage
  static Future<bool> setString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', value);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get data from storage
  static Future<String?> getString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_prefix$key');
    } catch (e) {
      return null;
    }
  }

  /// Remove data from storage
  static Future<bool> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear all data
  static Future<bool> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      return true;
    } catch (e) {
      return false;
    }
  }
}
