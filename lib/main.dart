import 'dart:convert';
import 'dart:io';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E293B),
          surfaceTint: const Color(0xFF6366F1),
        ),
        cardTheme: CardTheme(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: const Color(0xFF334155),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        final formattedText = isJsonContent ? _formatJson(decrypted) : decrypted;

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
  try {
    setState(() => isLoading = true);

    // Show picking progress
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CircularProgressIndicator(value: null, strokeWidth: 2),
            SizedBox(width: 16),
            Text("Selecting encrypted backup file..."),
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

    if (result == null || result.files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ No file selected")),
      );
      return;
    }

    final file = result.files.single;
    if (file.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Failed to read file")),
      );
      return;
    }

    // Show decryption progress
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            CircularProgressIndicator(value: null, strokeWidth: 2),
            SizedBox(width: 16),
            Text("Decrypting database..."),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    final fileBytes = file.bytes!;
    print('🔐 Decrypting ${fileBytes.length} bytes...');
    
    final decryptedBytes = decryptor.decryptBytesWithIvPrefix(fileBytes);

    // Verify decryption
    if (!_isValidSqliteDatabase(decryptedBytes)) {
      throw Exception("Decrypted data is not a valid SQLite database");
    }

    // Auto-download
    await _downloadFileWeb(decryptedBytes);

  } catch (e) {
    debugPrint("Error decrypting DB: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("❌ Decryption failed: ${e.toString()}"),
        duration: Duration(seconds: 5),
      ),
    );
  } finally {
    setState(() => isLoading = false);
  }
}

bool _isValidSqliteDatabase(Uint8List data) {
  if (data.length < 16) return false;
  
  // Check SQLite magic header
  final header = String.fromCharCodes(data.sublist(0, 15));
  return header == 'SQLite format 3';
}

Future<void> _downloadFileWeb(Uint8List decryptedBytes) async {
  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final filename = "ravamate_backup_$timestamp.sqlite";
  
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
              Text("Download Complete!", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          Text("✓ File: $filename"),
          Text("✓ Size: ${(decryptedBytes.length / 1024 / 1024).toStringAsFixed(2)} MB"),
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Secure Decryptor",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("About"),
                  content: const Text(
                    "Enter your 32-byte encryption key. The default key is pre-filled for convenience.\n\nAES-256 requires exactly 32 bytes for the key.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF0F172A),
              const Color(0xFF1E293B),
            ],
            stops: const [0.0, 0.8],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Key Input Section
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            "Encryption Key",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          // Visibility toggle
                          IconButton(
                            icon: Icon(
                              _showKey ? Icons.visibility_off : Icons.visibility,
                              color: Colors.white.withOpacity(0.6),
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _showKey = !_showKey;
                              });
                            },
                          ),
                          // Reset to default button
                          IconButton(
                            icon: const Icon(Icons.restart_alt_rounded),
                            color: Colors.white.withOpacity(0.6),
                            iconSize: 20,
                            onPressed: _resetToDefaultKey,
                            tooltip: "Reset to default key",
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _keyController,
                        focusNode: _keyFocusNode,
                        obscureText: !_showKey,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: "Enter your 32-byte encryption key...",
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearKey,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {}); // Rebuild to update character count
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            "${_keyController.text.length} characters",
                            style: TextStyle(
                              color: _keyController.text.length == 32
                                  ? const Color(0xFF10B981)
                                  : _keyController.text.length < 32
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFFEF4444),
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (_keyController.text.length != 32)
                            Text(
                              "Recommended: 32 characters",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Decrypt Button Section
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF818CF8),
                              const Color(0xFF6366F1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.lock_open_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      FilledButton.icon(
                        onPressed: isLoading ? null : pickAndDecryptFile,
                        icon: isLoading 
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              )
                            : const Icon(Icons.file_open_rounded, size: 20),
                        label: Text(
                          isLoading ? "Decrypting..." : "Select & Decrypt File",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: isLoading ? null : pickAndDecryptDatabase,
                      icon: const Icon(Icons.storage_rounded, size: 20),
                      label: const Text("Select & Decrypt Database"),
                       style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                    ),
                    
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Results section
              if (decryptedText.isNotEmpty)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                "Decrypted Content",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              if (isJson)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF10B981).withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    "JSON",
                                    style: TextStyle(
                                      color: const Color(0xFF10B981),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                decryptedText,
                                style: TextStyle(
                                  fontSize: isJson ? 13 : 14,
                                  color: Colors.white.withOpacity(0.9),
                                  fontFamily: isJson ? 'FiraCode' : null,
                                  fontFamilyFallback: isJson ? ['Monospace'] : null,
                                ),
                              ),
                            ),
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