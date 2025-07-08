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



}
