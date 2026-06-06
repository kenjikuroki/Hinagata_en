class AppEnvConfig {
  // ============================================================
  // NEW APP SETUP: Change these values when copying template
  // ============================================================
  static const String appUniqueId   = 'APP0001';
  static const String appName       = 'SwipeDrill';
  static const String iosBannerId   = 'ca-app-pub-3331079517737737/7520491853';
  static const String iosInterId    = 'ca-app-pub-3331079517737737/2268165171';
  static const String iosPurchaseId = 'unlock_linux';
  static const String iosAdAppId    = 'ca-app-pub-3331079517737737~1146655193';

  // ============================================================
  // COMMON — 変更不要
  // ============================================================
  static const String _masterGasUrl =
      'https://script.google.com/macros/s/AKfycbz43Z0CrLEsjZWHERQRH_XA8zQzm7Ca0x9YVU1lRRB5TQir_7plJIdt1-Ry0MFiY4xrvw/exec';
  static const String _questionsBaseUrl =
      'https://script.google.com/macros/s/AKfycbzhz1_l8Kk-sHQj025uhoR5EJLVBb1UeIozSbvryu1qF7HoN3eG320O57-M9VjObdSCLg/exec';

  static String get masterUrl    => '$_masterGasUrl?id=$appUniqueId';
  static String get questionsUrl => '$_questionsBaseUrl?id=$appUniqueId';
}
