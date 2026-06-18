import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});
