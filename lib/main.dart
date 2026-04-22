import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'decryptor.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Decryptor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5CF6),
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: const Color(0xFF1E293B),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E293B),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const DecryptorPage(),
    );
  }
}

class DecryptorPage extends StatefulWidget {
  const DecryptorPage({super.key});

  @override
  State<DecryptorPage> createState() => _DecryptorPageState();
}

class _DecryptorPageState extends State<DecryptorPage> {
  String decryptedText = "";
  bool isLoading = false;
  bool isJson = false;
  final TextEditingController _keyController = TextEditingController();
  final FocusNode _keyFocusNode = FocusNode();
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    // Set default key
    _keyController.text = "ravamate@2025_secure_32bit_key!!";
  }

  @override
  void dispose() {
    _keyController.dispose();
    _keyFocusNode.dispose();
    super.dispose();
  }

  Decryptor get decryptor => Decryptor(_keyController.text);

  Future<void> pickAndDecryptFile() async {
    // Validate key length (AES-256 requires 32 bytes)
    if (_keyController.text.isEmpty) {
      setState(() {
        decryptedText = "❌ Error: Encryption key cannot be empty";
      });
      return;
    }

    try {
      setState(() {
        isLoading = true;
        isJson = false;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'enc'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final decrypted = decryptor.decryptWithIvPrefix(fileBytes);

        // Check if the decrypted content is JSON
        final isJsonContent = _isValidJson(decrypted);
        final formattedText =
            isJsonContent ? _formatJson(decrypted) : decrypted;

        setState(() {
          decryptedText = formattedText;
          isJson = isJsonContent;
        });
      } else {
        setState(() {
          decryptedText = "No file selected.";
          isJson = false;
        });
      }
    } catch (e) {
      setState(() {
        decryptedText = "❌ Error: $e";
        isJson = false;
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> pickAndDecryptDatabase() async {
    if (!mounted) return;

    try {
      setState(() => isLoading = true);

      // Show initial snackbar
      final initialSnackBar = SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text("Selecting encrypted backup file..."),
          ],
        ),
        duration: const Duration(seconds: 2),
      );

      ScaffoldMessenger.of(context).showSnackBar(initialSnackBar);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['enc'],
        withData: true,
        allowMultiple: false,
      );

      // Hide the initial snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (result == null ||
          result.files.isEmpty ||
          result.files.single.bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No file selected")),
        );
        return;
      }

      if (!mounted) return;

      // Show decryption progress
      final decryptSnackBar = SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text("Decrypting database..."),
          ],
        ),
        duration: const Duration(seconds: 30),
      );

      ScaffoldMessenger.of(context).showSnackBar(decryptSnackBar);

      // Small delay to ensure snackbar is displayed
      await Future.delayed(const Duration(milliseconds: 100));

      final fileBytes = result.files.single.bytes!;

      final decryptedBytes = await compute(
        (bytes) => decryptor.decryptBytesWithIvPrefix(bytes),
        fileBytes,
      );

      if (!_isValidSqliteDatabase(decryptedBytes)) {
        throw Exception("Decrypted data is not a valid SQLite database");
      }

      // Hide decryption snackbar before showing success
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      await _downloadFileWeb(decryptedBytes, 'sqlite');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Database decrypted successfully!"),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint("Error decrypting DB: $e");

      // Hide any showing snackbars
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Decryption failed: ${e.toString()}"),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> pickAndDecryptCsv() async {
    if (!mounted) return;
    try {
      setState(() => isLoading = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(width: 16),
              Text("Selecting encrypted file..."),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['enc'],
        withData: true,
        allowMultiple: false,
      );

      if (result == null ||
          result.files.isEmpty ||
          result.files.single.bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No file selected")),
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();

      final fileBytes = result.files.single.bytes!;
      final decrypted = decryptor.decryptBytesWithIvPrefixNew(fileBytes);
      final csvData = _convertToCsv(decrypted);

      if (!mounted) return;
      await _downloadTextFileWeb(csvData, 'csv');
    } catch (e) {
      debugPrint("Error decrypting CSV: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Decryption failed: ${e.toString()}"),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  String _convertToCsv(String jsonData) {
    try {
      final data = json.decode(jsonData.trim());
      if (data is Map) {
        return _mapToCsv(data);
      } else if (data is List) {
        return _listToCsv(data);
      }
      return jsonData;
    } catch (e) {
      return jsonData;
    }
  }

  String _mapToCsv(Map data) {
    if (data.isEmpty) return '';
    final headers = data.keys.map((k) => '"$k"').join(',');
    final values = data.values.map((v) => '"${_escapeCsv(v)}"').join(',');
    return '$headers\n$values';
  }

  String _listToCsv(List data) {
    if (data.isEmpty) return '';
    if (data.first is Map) {
      final allKeys = <String>{};
      for (final item in data) {
        if (item is Map) allKeys.addAll(item.keys.map((k) => k.toString()));
      }
      final headers = allKeys.map((k) => '"$k"').join(',');
      final rows = data.map((item) {
        if (item is Map) {
          return allKeys.map((k) => '"${_escapeCsv(item[k])}"').join(',');
        }
        return '';
      }).join('\n');
      return '$headers\n$rows';
    }
    return data.map((v) => '"${_escapeCsv(v)}"').join(',');
  }

  String _escapeCsv(dynamic value) {
    if (value == null) return '';
    final str = value.toString();
    return str.replaceAll('"', '""').replaceAll('\n', ' ').replaceAll('\r', '');
  }

  bool _isValidSqliteDatabase(Uint8List data) {
    if (data.length < 16) return false;
    final header = String.fromCharCodes(data.sublist(0, 15));
    return header == 'SQLite format 3';
  }

  Future<void> _downloadFileWeb(Uint8List decryptedBytes, String type) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final extension = type == 'sqlite' ? 'sqlite' : 'csv';
    final filename = "ravamate_backup_$timestamp.$extension";

    // Create blob and download URL
    final blob = html.Blob([decryptedBytes], 'application/octet-stream');
    final url = html.Url.createObjectUrlFromBlob(blob);

    // Trigger download
    final anchor = html.AnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);

    // Cleanup
    html.Url.revokeObjectUrl(url);

    // Show success message
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.download_done, color: Colors.green),
                SizedBox(width: 8),
                Text("Download Complete!",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 8),
            Text("✓ File: $filename"),
            Text(
                "✓ Size: ${(decryptedBytes.length / 1024 / 1024).toStringAsFixed(2)} MB"),
            Text("✓ Check your downloads folder"),
          ],
        ),
        duration: Duration(seconds: 8),
        backgroundColor: Colors.green[50],
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.green,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  Future<void> _downloadTextFileWeb(String content, String type) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filename = "ravamate_export_$timestamp.$type";

    final bytes = content.codeUnits;
    final blob = html.Blob([Uint8List.fromList(bytes)], 'text/plain');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement()
      ..href = url
      ..download = filename
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    html.document.body?.children.remove(anchor);
    html.Url.revokeObjectUrl(url);

    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.download_done, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text("CSV Downloaded!",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 8),
            Text("✓ File: $filename",
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isValidJson(String text) {
    try {
      final trimmed = text.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}') ||
          trimmed.startsWith('[') && trimmed.endsWith(']')) {
        json.decode(trimmed);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  String _formatJson(String jsonString) {
    try {
      final parsed = json.decode(jsonString.trim());
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(parsed);
    } catch (e) {
      return jsonString; // Return original if formatting fails
    }
  }

  void _resetToDefaultKey() {
    setState(() {
      _keyController.text = "ravamate@2025_secure_32bit_key!!";
    });
  }

  void _clearKey() {
    setState(() {
      _keyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E1B4B),
              Color(0xFF0F172A),
              Color(0xFF020617),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.lock_open_rounded,
                        color: Color(0xFF8B5CF6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "Secure Decryptor",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.help_outline_rounded),
                    onPressed: () => _showHelpDialog(context),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildKeySection(),
                    const SizedBox(height: 24),
                    _buildDecryptButtons(),
                    const SizedBox(height: 24),
                    if (decryptedText.isNotEmpty) _buildResultsSection(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeySection() {
    final keyLength = _keyController.text.length;
    final isValidKey = keyLength == 32;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B).withOpacity(0.8),
            const Color(0xFF1E293B).withOpacity(0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isValidKey
              ? const Color(0xFF10B981).withOpacity(0.3)
              : Colors.white.withOpacity(0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.key_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              const Text(
                "Encryption Key",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              _buildKeyStatus(keyLength),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _keyController,
            focusNode: _keyFocusNode,
            obscureText: !_showKey,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: "Enter your encryption key...",
              prefixIcon: Icon(
                _showKey ? Icons.vpn_key_rounded : Icons.password_rounded,
                color: Colors.white38,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      _showKey
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.white54,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                    tooltip: _showKey ? "Hide key" : "Show key",
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white54),
                    onPressed: _resetToDefaultKey,
                    tooltip: "Reset to default",
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildKeyHint(
                icon: isValidKey
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                label: "$keyLength / 32 characters",
                color: isValidKey
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 16),
              if (!isValidKey)
                Expanded(
                  child: _buildKeyHint(
                    icon: Icons.warning_amber_rounded,
                    label: keyLength < 32 ? "Key too short" : "Key too long",
                    color: const Color(0xFFEF4444),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyStatus(int length) {
    final isValid = length == 32;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isValid
            ? const Color(0xFF10B981).withOpacity(0.15)
            : const Color(0xFFF59E0B).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isValid
              ? const Color(0xFF10B981).withOpacity(0.3)
              : const Color(0xFFF59E0B).withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isValid ? Icons.verified_rounded : Icons.warning_amber_rounded,
            size: 14,
            color: isValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 6),
          Text(
            isValid ? "Valid" : "Check key",
            style: TextStyle(
              color:
                  isValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyHint(
      {required IconData icon, required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildDecryptButtons() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF8B5CF6).withOpacity(0.15),
            const Color(0xFF6366F1).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.4),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.lock_open_rounded,
              color: Colors.white,
              size: 42,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Ready to Decrypt",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Select a file or database to decrypt",
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _DecryptButton(
                  icon: Icons.description_rounded,
                  label: "Decrypt File",
                  subtitle: ".txt, .enc",
                  isLoading: isLoading,
                  onPressed: pickAndDecryptFile,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DecryptButton(
                  icon: Icons.table_chart_rounded,
                  label: "Decrypt CSV",
                  subtitle: ".enc → .csv",
                  isLoading: isLoading,
                  onPressed: pickAndDecryptCsv,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DecryptButton(
                  icon: Icons.storage_rounded,
                  label: "Decrypt DB",
                  subtitle: ".enc → .sqlite",
                  isLoading: isLoading,
                  onPressed: pickAndDecryptDatabase,
                  color: const Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.8),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  "Decrypted Successfully",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (isJson)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withOpacity(0.3),
                      ),
                    ),
                    child: const Text(
                      "JSON",
                      style: TextStyle(
                        color: Color(0xFF3B82F6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                decryptedText,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.9),
                  fontFamily: isJson ? 'monospace' : null,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.help_outline_rounded,
                  color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(width: 12),
            const Text("How to Use"),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HelpItem(
              number: "1",
              title: "Enter Key",
              description: "Enter your 32-byte encryption key",
            ),
            SizedBox(height: 16),
            _HelpItem(
              number: "2",
              title: "Select File",
              description: "Choose a .txt or .enc file to decrypt",
            ),
            SizedBox(height: 16),
            _HelpItem(
              number: "3",
              title: "Decrypt Database",
              description: "Extract encrypted SQLite databases",
            ),
            SizedBox(height: 16),
            Text(
              "AES-256 encryption requires exactly 32 characters.",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got it!"),
          ),
        ],
      ),
    );
  }
}

class _DecryptButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isLoading;
  final VoidCallback onPressed;
  final Color color;

  const _DecryptButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isLoading,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _HelpItem({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF8B5CF6),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
