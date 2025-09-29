// database/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'db_schema.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  static Database? _db;

  DatabaseHelper._internal();

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'teravaani.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(DBSchema.createCropGuides);
    await db.execute(DBSchema.createFertilizerPlans);
    await db.execute(DBSchema.createWeatherCache);
    await db.execute(DBSchema.createMarketRates);
    await db.execute(DBSchema.createUserSettings);
    await db.execute(DBSchema.createVoiceLogs);
    await db.execute(DBSchema.createTTSCache);
    await db.execute(DBSchema.createQueryResponse);
    await db.execute(DBSchema.createPostHarvestOfflineTable);

    // 🌾 Prepopulate Rice-related query-response data
    await db.insert('query_response', {
      'query': 'What is the ideal temperature for rice?'.toLowerCase(),
      'response': 'Rice grows best at temperatures between 20°C and 35°C.'
    });

    await db.insert('query_response', {
      'query': 'How much water does rice need?'.toLowerCase(),
      'response': 'Rice requires continuous flooding with 5 to 10 cm of water throughout most of its growth.'
    });

    await db.insert('query_response', {
      'query': 'What is the planting season for rice?'.toLowerCase(),
      'response': 'In India, rice is usually planted during the Kharif season, which starts in June or July.'
    });

    await db.insert('query_response', {
      'query': 'Tell me about rice fertilizers'.toLowerCase(),
      'response': 'Rice cultivation benefits from fertilizers rich in nitrogen, phosphorus, and potassium.'
    });

    await db.insert('query_response', {
      'query': 'What are the different varieties of rice?'.toLowerCase(),
      'response': 'Popular varieties of rice in India include Basmati, Sona Masuri, IR64, Ponni, and Gobindobhog.'
    });

    await db.insert('query_response', {
      'query': 'What is Basmati rice?'.toLowerCase(),
      'response': 'Basmati rice is a long-grain aromatic rice grown mainly in India and Pakistan, known for its distinct fragrance and fluffy texture.'
    });

    await db.insert('query_response', {
      'query': 'How long does rice take to grow?'.toLowerCase(),
      'response': 'Rice generally takes about 3 to 6 months to grow, depending on the variety and environmental conditions.'
    });

    await db.insert('query_response', {
      'query': 'What pests affect rice crops?'.toLowerCase(),
      'response': 'Common pests in rice cultivation include stem borers, leaf folders, brown planthoppers, and gall midges.'
    });

    // await db.insert('query_response', {
    //   'query': 'What diseases affect rice plants?'.toLowerCase(),
    //   'response': 'Major rice diseases include blast, sheath blight, bacterial leaf blight, and tungro virus.'
    // });

    await db.insert('query_response', {
      'query': 'What is the average yield of rice per hectare?'.toLowerCase(),
      'response': 'In India, the average yield of rice is around 2.7 to 3.5 tons per hectare, depending on the region and variety.'
    });

  }
  
  //Insert Voice Log
  Future<void> insertVoiceLog(String query, {String? context}) async {
    final dbClient = await db;
    await dbClient.insert('voice_logs', {
      'query': query,
      'context': context ?? 'general', // optional
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  //Insert User Settings Location 
  Future<void> insertOrUpdateUserSettings({
    required String language,
    required String state,
    required String district,
  }) async {
    final db = await this.db;
    final existing = await db.query('user_settings', limit: 1);

    if (existing.isEmpty) {
      await db.insert('user_settings', {
        'language': language,
        'state': state,
        'district': district,
      });
    } else {
      await db.update(
        'user_settings',
        {'language': language, 'state': state, 'district': district},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  //Get User Settings Location 
  Future<Map<String, dynamic>?> getUserSettings() async {
    final db = await this.db;
    final settings = await db.query('user_settings', limit: 1);
    return settings.isNotEmpty ? settings.first : null;
  }

  Future<void> insertQueryResponse(String query, String response) async {
    final db = await this.db;
    await db.insert(
      'query_response',
      {
        'query': query.toLowerCase(),
        'response': response,
        'timestamp': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getQueryResponse(String query) async {
    final db = await this.db;
    final result = await db.query(
      'query_response',
      where: 'LOWER(query) = ?',
      whereArgs: ['%' + query.toLowerCase() + '%'],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['response'] as String?;
    }
    return null;
  }

  Future<void> insertOfflinePostHarvestEvent(String userId, String cropName, String sowingDate) async {
    final db = await this.db;
    await db.insert(
      'post_harvest_queue',
      {
        'userId': userId,
        'cropName': cropName,
        'sowingDate': sowingDate,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getOfflinePostHarvestEvents() async {
    final db = await this.db;
    return db.query('post_harvest_queue');
  }

  Future<void> deleteOfflinePostHarvestEvent(int id) async {
    final db = await this.db;
    await db.delete('post_harvest_queue', where: 'id = ?', whereArgs: [id]);
  }


}
