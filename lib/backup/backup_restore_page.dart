import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'database_backup_service.dart';

class BackupRestorePage extends StatefulWidget {
  final Color primaryColor;

  const BackupRestorePage({
    super.key,
    required this.primaryColor,
  });

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  final DatabaseBackupService _backupService = DatabaseBackupService();

  bool _isBackingUp = false;
  String _message =
      'Create a complete SQLite backup of this school database.';
  bool _hasError = false;

  Future<void> _createBackup() async {
    if (_isBackingUp) return;

    setState(() {
      _isBackingUp = true;
      _hasError = false;
      _message = 'Preparing and verifying your database backup...';
    });

    try {
      final location = await _backupService.createBackup();

      if (!mounted) return;

      setState(() {
        if (location == null || location.isEmpty) {
          _message = 'Backup cancelled. No file was saved.';
        } else {
          _message = 'Backup saved successfully:\n$location';
        }
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _hasError = true;
        _message = 'Backup could not be completed:\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
        });
      }
    }
  }


  Future<void> _restoreBackup() async {
    if (_isBackingUp) return;

    try {
      final selection = await FilePicker.pickFiles(
        dialogTitle: 'Select TLC School System database backup',
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite', 'sqlite3'],
      );
      if (!mounted || selection.isEmpty) return;

      final backupPath = selection.first.path;
      if (backupPath == null || backupPath.isEmpty) {
        throw StateError('The selected file path could not be accessed.');
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm database restore'),
          content: const Text(
            'Restoring replaces the current school database with the selected '
            'backup. A separate safety backup of the current database will '
            'be created first. Continue only if you are certain this is the '
            'correct backup file.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore Database'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      setState(() {
        _isBackingUp = true;
        _hasError = false;
        _message = 'Validating backup and preparing a safety copy...';
      });

      final safetyPath = await _backupService.restoreBackup(backupPath);
      if (!mounted) return;
      setState(() {
        _message = 'Database restored and verified successfully. '
            'Your pre-restore safety copy is saved at:\n$safetyPath';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _message = 'Restore could not be completed:\n$error';
      });
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Backup & Restore',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Protect your school records with a complete database backup.',
                style: TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 25),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 27,
                            backgroundColor: primary.withValues(alpha: 0.10),
                            child: Icon(
                              Icons.backup_outlined,
                              size: 30,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 15),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Full Database Backup',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'Save all database tables and records '
                                  'in one SQLite .db file.',
                                  style: TextStyle(color: Colors.blueGrey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isBackingUp ? null : _createBackup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                            ),
                          ),
                          icon: _isBackingUp
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_alt_rounded),
                          label: Text(
                            _isBackingUp
                                ? 'Creating Backup...'
                                : 'Create Database Backup',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isBackingUp ? null : _restoreBackup,
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Restore from Backup'),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _hasError
                              ? Colors.red.withValues(alpha: 0.07)
                              : Colors.blueGrey.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _hasError
                                  ? Icons.error_outline
                                  : Icons.info_outline,
                              color: _hasError
                                  ? Colors.red
                                  : Colors.blueGrey,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                _message,
                                style: TextStyle(
                                  color: _hasError
                                      ? Colors.red.shade800
                                      : Colors.blueGrey.shade800,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: Colors.green,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Important Data Safety Information',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      const Text(
                        '• The backup is a complete SQLite database file.\n'
                        '• Save it to a safe location outside the app folder.\n'
                        '• Keep an additional copy on a separate drive.\n'
                        '• Creating a backup does not delete or replace records.\n'
                        '• Restore accepts only a compatible, verified database backup.\n'
                        '• A pre-restore safety copy is created before replacement.\n'
                        '• If verification fails, the previous database is restored.',
                        style: TextStyle(
                          height: 1.8,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
