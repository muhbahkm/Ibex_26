import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.databaseSha256,
  });

  final int schemaVersion;
  final DateTime createdAtUtc;
  final String databaseSha256;

  Map<String, Object> toJson() => {
        'schema_version': schemaVersion,
        'created_at_utc': createdAtUtc.toUtc().toIso8601String(),
        'database_sha256': databaseSha256,
      };

  static BackupManifest fromJson(Map<String, Object?> json) => BackupManifest(
        schemaVersion: json['schema_version']! as int,
        createdAtUtc: DateTime.parse(json['created_at_utc']! as String).toUtc(),
        databaseSha256: json['database_sha256']! as String,
      );
}

class EncryptedBackupService {
  const EncryptedBackupService();

  Future<BackupManifest> createClosedDatabaseBackup({
    required File sourceDatabase,
    required Directory destinationDirectory,
    required int schemaVersion,
  }) async {
    if (!await sourceDatabase.exists()) {
      throw StateError('Source database does not exist.');
    }
    await destinationDirectory.create(recursive: true);

    final bytes = await sourceDatabase.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final manifest = BackupManifest(
      schemaVersion: schemaVersion,
      createdAtUtc: DateTime.now().toUtc(),
      databaseSha256: digest,
    );

    final dbTarget = File(p.join(destinationDirectory.path, 'ibex.db.enc'));
    final manifestTarget = File(p.join(destinationDirectory.path, 'manifest.json'));
    await dbTarget.writeAsBytes(bytes, flush: true);
    await manifestTarget.writeAsString(jsonEncode(manifest.toJson()), flush: true);
    return manifest;
  }

  Future<BackupManifest> validateBackup(Directory backupDirectory) async {
    final dbFile = File(p.join(backupDirectory.path, 'ibex.db.enc'));
    final manifestFile = File(p.join(backupDirectory.path, 'manifest.json'));
    if (!await dbFile.exists() || !await manifestFile.exists()) {
      throw StateError('Backup is incomplete.');
    }

    final decoded = jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    final manifest = BackupManifest.fromJson(decoded);
    final digest = sha256.convert(await dbFile.readAsBytes()).toString();
    if (digest != manifest.databaseSha256) {
      throw StateError('Backup checksum mismatch.');
    }
    return manifest;
  }

  Future<void> restoreValidatedBackup({
    required Directory backupDirectory,
    required File targetDatabase,
  }) async {
    await validateBackup(backupDirectory);
    final source = File(p.join(backupDirectory.path, 'ibex.db.enc'));
    await targetDatabase.parent.create(recursive: true);

    final temp = File('${targetDatabase.path}.restore.tmp');
    if (await temp.exists()) await temp.delete();
    await source.copy(temp.path);

    if (await targetDatabase.exists()) {
      final safety = File('${targetDatabase.path}.pre_restore');
      if (await safety.exists()) await safety.delete();
      await targetDatabase.rename(safety.path);
      try {
        await temp.rename(targetDatabase.path);
        await safety.delete();
      } catch (_) {
        if (await targetDatabase.exists()) await targetDatabase.delete();
        await safety.rename(targetDatabase.path);
        rethrow;
      }
    } else {
      await temp.rename(targetDatabase.path);
    }
  }
}
