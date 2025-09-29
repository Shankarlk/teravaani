
class DBSchema {
  static const createCropGuides = '''
    CREATE TABLE crop_guides (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      crop_name TEXT NOT NULL,
      stage TEXT NOT NULL,
      advice TEXT NOT NULL
    );
  ''';

  static const createFertilizerPlans = '''
    CREATE TABLE fertilizer_plans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      crop_name TEXT NOT NULL,
      stage TEXT NOT NULL,
      fertilizer_name TEXT NOT NULL,
      dosage TEXT NOT NULL,
      timing TEXT NOT NULL
    );
  ''';

  static const createWeatherCache = '''
    CREATE TABLE weather_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      district TEXT NOT NULL,
      forecast TEXT NOT NULL,
      fetched_at TEXT NOT NULL
    );
  ''';

  static const createMarketRates = '''
    CREATE TABLE market_rates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      crop_name TEXT NOT NULL,
      market TEXT NOT NULL,
      price REAL NOT NULL,
      date TEXT NOT NULL
    );
  ''';

  static const createUserSettings = '''
    CREATE TABLE user_settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      language TEXT DEFAULT 'en',
      state TEXT,
      district TEXT
    );
  ''';

  static const createVoiceLogs = '''
    CREATE TABLE voice_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      query TEXT NOT NULL,
      context TEXT,
      timestamp TEXT DEFAULT CURRENT_TIMESTAMP
    );
  ''';

  static const createTTSCache = '''
    CREATE TABLE tts_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      context TEXT NOT NULL,
      message TEXT NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );
  ''';

  static const createQueryResponse = '''
  CREATE TABLE query_response (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query TEXT NOT NULL,
    response TEXT NOT NULL,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
  );
''';

  static const createPostHarvestOfflineTable = '''
          CREATE TABLE post_harvest_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            userId TEXT,
            cropName TEXT,
            sowingDate TEXT
          );
        ''';

}
