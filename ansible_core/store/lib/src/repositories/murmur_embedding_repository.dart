import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/drift.dart';
import '../db/app_database.dart';

class DriftMurmurEmbeddingRepository {
  final AppDatabase _db;
  const DriftMurmurEmbeddingRepository(this._db);

  Future<void> upsert({
    required String contentItemId,
    required String modelVersion,
    required List<double> vector,
  }) async {
    final blob = _encodeVector(vector);
    await _db.into(_db.murmurEmbeddings).insertOnConflictUpdate(
      MurmurEmbeddingsCompanion.insert(
        contentItemId: contentItemId,
        modelVersion: modelVersion,
        vectorBlob: blob,
        computedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<List<double>?> getVector(String contentItemId) async {
    final row = await (_db.select(_db.murmurEmbeddings)
          ..where((t) => t.contentItemId.equals(contentItemId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _decodeVector(row.vectorBlob);
  }

  Future<List<({String contentItemId, List<double> vector})>> getAll({
    DateTime? since,
  }) async {
    final query = _db.select(_db.murmurEmbeddings);
    if (since != null) {
      query.where((t) => t.computedAt.isBiggerOrEqualValue(since));
    }
    final rows = await query.get();
    return rows
        .map((r) => (
              contentItemId: r.contentItemId,
              vector: _decodeVector(r.vectorBlob),
            ))
        .toList();
  }

  Future<Set<String>> allIndexedIds() async {
    final rows = await _db.select(_db.murmurEmbeddings).get();
    return {for (final r in rows) r.contentItemId};
  }

  Future<void> delete(String contentItemId) async {
    await (_db.delete(_db.murmurEmbeddings)
          ..where((t) => t.contentItemId.equals(contentItemId)))
        .go();
  }

  static String _encodeVector(List<double> vector) {
    final bytes = Float32List.fromList(
      vector.map((v) => v.toDouble()).toList(),
    ).buffer.asUint8List();
    return base64Encode(bytes);
  }

  static List<double> _decodeVector(String blob) {
    final bytes = base64Decode(blob);
    final floats = bytes.buffer.asFloat32List();
    return floats.map((f) => f.toDouble()).toList();
  }
}
