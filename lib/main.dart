import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'auth_service.dart';
import 'decryptor.dart';
import 'login_page.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MyApp());
}

// ─── Design Tokens & Constants ───────────────────────────────────────────────

const Color kPrimary = Color(0xFF8B5CF6);
const Color kPrimaryLight = Color(0xFFA78BFA);
const Color kIndigo = Color(0xFF6366F1);
const Color kCyan = Color(0xFF06B6D4);
const Color kGreen = Color(0xFF10B981);
const Color kAmber = Color(0xFFF59E0B);
const Color kRed = Color(0xFFEF4444);

const Color kBgDark = Color(0xFF090D16);
const Color kSurface = Color(0xFF0F172A);
const Color kCard = Color(0xFF131D33);
const Color kCardElevated = Color(0xFF19253F);
const Color kBorder = Color(0xFF1E2E4A);
const Color kBorderGlow = Color(0xFF3B4E75);

enum DecryptMode { textOrEnc, csv, sqlite }

enum DecryptState { idle, decrypting, success, error }

// ─── App Root ────────────────────────────────────────────────────────────────

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FDC Secure Decryptor Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBgDark,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          brightness: Brightness.dark,
          surface: kSurface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0A1020),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 1.5),
          ),
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      home: const StudioAuthGate(),
    );
  }
}

// ─── Studio Auth Gate ────────────────────────────────────────────────────────

class StudioAuthGate extends StatefulWidget {
  const StudioAuthGate({super.key});

  @override
  State<StudioAuthGate> createState() => _StudioAuthGateState();
}

class _StudioAuthGateState extends State<StudioAuthGate> {
  Timer? _inactivityChecker;

  @override
  void initState() {
    super.initState();
    AuthService().initSession();
    _startInactivityChecker();
  }

  @override
  void dispose() {
    _inactivityChecker?.cancel();
    super.dispose();
  }

  void _startInactivityChecker() {
    _inactivityChecker?.cancel();
    // Check every 30 seconds for session timeout
    _inactivityChecker = Timer.periodic(const Duration(seconds: 30), (_) {
      final session = AuthService().currentSession;
      if (session != null && session.isExpired) {
        AuthService().logout();
      }
    });
  }

  void _onUserInteraction() {
    AuthService().refreshActivity();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthSession?>(
      valueListenable: AuthService().sessionNotifier,
      builder: (context, session, _) {
        if (session != null && !session.isExpired) {
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _onUserInteraction(),
            onPointerMove: (_) => _onUserInteraction(),
            child: const DecryptorStudioPage(),
          );
        }
        return StudioLoginPage(
          onAuthenticated: () {},
        );
      },
    );
  }
}

// ─── Main Studio Page ────────────────────────────────────────────────────────

class DecryptorStudioPage extends StatefulWidget {
  const DecryptorStudioPage({super.key});

  @override
  State<DecryptorStudioPage> createState() => _DecryptorStudioPageState();
}

class _DecryptorStudioPageState extends State<DecryptorStudioPage>
    with TickerProviderStateMixin {
  // State
  DecryptState _state = DecryptState.idle;
  DecryptMode _selectedMode = DecryptMode.textOrEnc;

  // Key field
  final TextEditingController _keyController = TextEditingController();
  final FocusNode _keyFocusNode = FocusNode();
  bool _showKey = false;

  // Active file & result
  PlatformFile? _stagedFile;
  String _decryptedText = '';
  Uint8List? _decryptedBytes;
  bool _isJson = false;
  String _statusMessage = '';
  double _decryptProgress = 0.0;
  String _currentStepText = '';
  String _downloadFileName = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Desktop Web Toast Notification state
  _WebToast? _activeToast;
  Timer? _toastTimer;

  // Animations
  late final AnimationController _bgAnimationCtrl;
  late final AnimationController _radarCtrl;
  late final AnimationController _cipherStreamCtrl;

  @override
  void initState() {
    super.initState();
    _keyController.text = 'ravamate@2025_secure_32bit_key!!';

    // Ambient background drifting orbs
    _bgAnimationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);

    // Cryptographic radar HUD animation
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // Cipher matrix stream ticker
    _cipherStreamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _bgAnimationCtrl.dispose();
    _radarCtrl.dispose();
    _cipherStreamCtrl.dispose();
    _keyController.dispose();
    _keyFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Decryptor get _decryptor => Decryptor(_keyController.text);

  // ─── Cryptographic Action Pipeline ──────────────────────────────────────────

  Future<void> _handleFileSelection() async {
    final extensions = _modeExtensions(_selectedMode);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _stagedFile = result.files.single;
        });
        // Immediately start decryption pipeline
        await _runDecryptionPipeline();
      }
    } catch (e) {
      _setError('Failed to select file: $e');
    }
  }

  List<String> _modeExtensions(DecryptMode mode) {
    switch (mode) {
      case DecryptMode.textOrEnc:
        return ['txt', 'enc'];
      case DecryptMode.csv:
        return ['enc'];
      case DecryptMode.sqlite:
        return ['enc'];
    }
  }

  Future<void> _runDecryptionPipeline() async {
    final file = _stagedFile;
    if (file == null || file.bytes == null) {
      _setError('No file loaded to decrypt.');
      return;
    }

    if (_keyController.text.length != 32) {
      _setError(
          'Invalid Key: AES-256 requires exactly 32 characters (currently ${_keyController.text.length}).');
      return;
    }

    setState(() {
      _state = DecryptState.decrypting;
      _decryptProgress = 0.15;
      _currentStepText = 'Reading 16-byte initialization vector (IV)...';
      _statusMessage = 'Analyzing payload structure...';
    });

    // Step 1: Yield frame so UI renders immediately without hitch
    await Future.delayed(const Duration(milliseconds: 260));

    try {
      final fileBytes = file.bytes!;
      if (fileBytes.length < 16) {
        throw Exception('File too short to contain a valid 16-byte IV prefix');
      }

      setState(() {
        _decryptProgress = 0.45;
        _currentStepText = 'Initializing AES-256-CBC cipher matrix...';
        _statusMessage = 'Applying key and decrypting ciphertext...';
      });

      // Step 2: Yield frame for animation smoothness
      await Future.delayed(const Duration(milliseconds: 280));

      String resultText = '';
      Uint8List? resultBytes;
      String downloadName = '';
      bool isJsonContent = false;

      // Step 3: Decrypt based on mode
      if (_selectedMode == DecryptMode.sqlite) {
        setState(() {
          _decryptProgress = 0.75;
          _currentStepText = 'Validating SQLite 3 database header...';
        });
        await Future.delayed(const Duration(milliseconds: 200));

        final decrypted = _decryptor.decryptBytesWithIvPrefix(fileBytes);
        if (!_isValidSqliteDatabase(decrypted)) {
          throw Exception('Decrypted data is not a valid SQLite database format');
        }

        resultBytes = decrypted;
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        downloadName = file.name.toLowerCase().endsWith('.enc')
            ? '${file.name.substring(0, file.name.length - 4)}.sqlite'
            : 'database_$timestamp.sqlite';

        // Auto trigger download for binary SQLite
        await _downloadFileWeb(decrypted, downloadName);
      } else if (_selectedMode == DecryptMode.csv) {
        setState(() {
          _decryptProgress = 0.75;
          _currentStepText = 'Converting decrypted records into CSV table...';
        });
        await Future.delayed(const Duration(milliseconds: 200));

        final decrypted = _decryptor.decryptBytesWithIvPrefixNew(fileBytes);
        final csvData = _convertToCsv(decrypted);
        resultText = csvData;

        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        downloadName = file.name.toLowerCase().endsWith('.enc')
            ? '${file.name.substring(0, file.name.length - 4)}.csv'
            : 'export_$timestamp.csv';

        // Auto trigger download for CSV
        await _downloadTextFileWeb(csvData, downloadName);
      } else {
        // Text or generic .enc
        setState(() {
          _decryptProgress = 0.75;
          _currentStepText = 'Decoding payload & parsing format...';
        });
        await Future.delayed(const Duration(milliseconds: 200));

        final decrypted = _decryptor.decryptWithIvPrefix(fileBytes);
        isJsonContent = _isValidJson(decrypted);
        resultText = isJsonContent ? _formatJson(decrypted) : decrypted;

        if (file.name.toLowerCase().endsWith('.enc')) {
          downloadName =
              '${file.name.substring(0, file.name.length - 4)}.txt';
          // Auto trigger download for .enc files
          await _downloadTextFileWeb(resultText, downloadName);
        } else {
          downloadName = '${file.name}.decrypted.txt';
        }
      }

      setState(() {
        _decryptProgress = 1.0;
        _currentStepText = 'Decryption complete & verified!';
      });
      await Future.delayed(const Duration(milliseconds: 180));

      setState(() {
        _decryptedText = resultText;
        _decryptedBytes = resultBytes;
        _isJson = isJsonContent;
        _downloadFileName = downloadName;
        _state = DecryptState.success;
        _statusMessage = 'Decrypted successfully (${file.name})';
      });

      _showToast(
        'Decryption Complete',
        'Successfully decrypted ${file.name}',
        kGreen,
        Icons.verified_rounded,
      );
    } catch (e) {
      _setError('Decryption failed: $e');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _state = DecryptState.error;
      _statusMessage = message;
    });
    _showToast(
      'Decryption Failed',
      message,
      kRed,
      Icons.error_outline_rounded,
    );
  }

  void _resetWorkbench() {
    setState(() {
      _state = DecryptState.idle;
      _stagedFile = null;
      _decryptedText = '';
      _decryptedBytes = null;
      _downloadFileName = '';
      _statusMessage = '';
      _searchQuery = '';
      _searchController.clear();
    });
    _showToast(
      'Workbench Reset',
      'Cleared all inputs and decrypted outputs',
      kCyan,
      Icons.refresh_rounded,
    );
  }

  void _copyToClipboard() {
    if (_decryptedText.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _decryptedText));
    _showToast(
      'Copied to Clipboard',
      'Decrypted text ready to paste (${_decryptedText.length} characters)',
      kGreen,
      Icons.check_circle_rounded,
    );
  }

  void _showToast(String title, String msg, Color color, IconData icon) {
    _toastTimer?.cancel();
    setState(() {
      _activeToast = _WebToast(
        title: title,
        message: msg,
        color: color,
        icon: icon,
      );
    });
    _toastTimer = Timer(const Duration(milliseconds: 3800), () {
      if (!mounted) return;
      setState(() {
        _activeToast = null;
      });
    });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  bool _isValidJson(String text) {
    try {
      final t = text.trim();
      if ((t.startsWith('{') && t.endsWith('}')) ||
          (t.startsWith('[') && t.endsWith(']'))) {
        json.decode(t);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String _formatJson(String jsonString) {
    try {
      final parsed = json.decode(jsonString.trim());
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(parsed);
    } catch (_) {
      return jsonString;
    }
  }

  bool _isValidSqliteDatabase(Uint8List data) {
    if (data.length < 16) return false;
    return String.fromCharCodes(data.sublist(0, 15)) == 'SQLite format 3';
  }

  String _convertToCsv(String jsonData) {
    try {
      final data = json.decode(jsonData.trim());
      if (data is Map) return _mapToCsv(data);
      if (data is List) return _listToCsv(data);
      return jsonData;
    } catch (_) {
      return jsonData;
    }
  }

  String _mapToCsv(Map data) {
    if (data.isEmpty) return '';
    final headers = data.keys.map((k) => '"$k"').join(',');
    final values =
        data.values.map((v) => '"${_escapeCsv(v)}"').join(',');
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
    return value
        .toString()
        .replaceAll('"', '""')
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');
  }

  Future<void> _downloadFileWeb(Uint8List bytes, String filename) async {
    final blob = html.Blob([bytes], 'application/octet-stream');
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
    _showToast('Download Ready', 'Saved: $filename', kGreen,
        Icons.file_download_done_rounded);
  }

  Future<void> _downloadTextFileWeb(String content, String filename) async {
    final bytes = Uint8List.fromList(content.codeUnits);
    final blob = html.Blob([bytes], 'text/plain');
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
    _showToast('Download Ready', 'Saved: $filename', kGreen,
        Icons.file_download_done_rounded);
  }

  // ─── Build Method ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Ambient dynamic cyber background
          RepaintBoundary(
            child: _AnimatedBackground(controller: _bgAnimationCtrl),
          ),

          // Main desktop web container
          SafeArea(
            child: Column(
              children: [
                _buildWebHeader(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth >= 980;
                      if (isDesktop) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Left Column: Control Panel & Dropzone (fixed width)
                              SizedBox(
                                width: 440,
                                child: SingleChildScrollView(
                                  child: _buildLeftControlStation(),
                                ),
                              ),
                              const SizedBox(width: 24),
                              // Right Column: Output Studio Workbench (expands)
                              Expanded(
                                child: _buildRightWorkbench(),
                              ),
                            ],
                          ),
                        );
                      } else {
                        // Narrow / Mobile fallback layout
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          child: Column(
                            children: [
                              _buildLeftControlStation(),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 600,
                                child: _buildRightWorkbench(),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Desktop Web Floating Toast Notification (Top-Right HUD)
          Positioned(
            top: 20,
            right: 28,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              reverseDuration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                final offsetAnim = Tween<Offset>(
                  begin: const Offset(0.35, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ));
                return SlideTransition(
                  position: offsetAnim,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: _activeToast == null
                  ? const SizedBox.shrink()
                  : _WebToastCard(
                      key: ValueKey(_activeToast!.timestamp),
                      toast: _activeToast!,
                      onDismiss: () {
                        _toastTimer?.cancel();
                        setState(() => _activeToast = null);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Web Header ───────────────────────────────────────────────────────────

  Widget _buildWebHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: kBgDark.withOpacity(0.85),
        border: Border(
          bottom: BorderSide(color: kBorder.withOpacity(0.8)),
        ),
      ),
      child: Row(
        children: [
          // Logo & Studio Name
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kPrimary, kIndigo],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: kPrimary.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.shield_outlined,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    'FDC Decryptor Studio',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 10),
                  _BadgePill(
                    label: 'WEB EDITION',
                    color: kPrimary,
                  ),
                ],
              ),
              Text(
                'High-performance AES-256-CBC In-Browser Cryptographic Engine',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ],
          ),
          const Spacer(),

          // Telemetry status tags (Web app feel)
          const _StatusTag(
            icon: Icons.lock_outline_rounded,
            label: '100% Client-Side Sandbox',
            color: kGreen,
          ),
          const SizedBox(width: 12),
          const _StatusTag(
            icon: Icons.memory_rounded,
            label: 'Hardware Accelerated',
            color: kCyan,
          ),
          const SizedBox(width: 20),

          // Action buttons
          _HeaderBtn(
            icon: Icons.help_outline_rounded,
            label: 'Docs & Formats',
            onPressed: () => _showHelpDialog(context),
          ),
          const SizedBox(width: 8),
          _HeaderBtn(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            onPressed: _resetWorkbench,
          ),
          const SizedBox(width: 14),
          _buildOperatorSessionBadge(),
        ],
      ),
    );
  }

  Widget _buildOperatorSessionBadge() {
    final session = AuthService().currentSession;
    final username = session?.username ?? 'admin';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kCardElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: kGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Operator: $username',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () {
              AuthService().logout();
            },
            borderRadius: BorderRadius.circular(6),
            child: Tooltip(
              message: 'Lock Studio (Logout)',
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kRed.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kRed.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 11, color: Color(0xFFFCA5A5)),
                    SizedBox(width: 4),
                    Text(
                      'Lock',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFCA5A5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Left Control Station ──────────────────────────────────────────────────

  Widget _buildLeftControlStation() {
    final keyLen = _keyController.text.length;
    final isKeyValid = keyLen == 32;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Key Vault Panel
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _IconBadge(icon: Icons.vpn_key_rounded, color: kPrimary),
                  const SizedBox(width: 12),
                  const Text(
                    'Master Encryption Key',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  _StatusPill(isValid: isKeyValid, length: keyLen),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'AES-256 requires a precise 32-byte string to decipher payload blocks.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.45),
                ),
              ),
              const SizedBox(height: 14),

              // Key Input Field
              TextField(
                controller: _keyController,
                focusNode: _keyFocusNode,
                obscureText: !_showKey,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter 32-character key…',
                  prefixIcon: Icon(
                    _showKey ? Icons.key_rounded : Icons.password_rounded,
                    color: kPrimary.withOpacity(0.7),
                    size: 18,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconBtn(
                        icon: _showKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        tooltip: _showKey ? 'Hide key' : 'Show key',
                        onPressed: () => setState(() => _showKey = !_showKey),
                      ),
                      _IconBtn(
                        icon: Icons.restart_alt_rounded,
                        tooltip: 'Reset default key',
                        onPressed: () => setState(() => _keyController.text =
                            'ravamate@2025_secure_32bit_key!!'),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),

              // Progress indicator
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (keyLen / 32).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.white.withOpacity(0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    keyLen > 32
                        ? kRed
                        : isKeyValid
                            ? kGreen
                            : kPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 2. Mode Selector Tabs
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  _IconBadge(
                      icon: Icons.tune_rounded, color: kCyan),
                  SizedBox(width: 12),
                  Text(
                    'Decryption Target',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ModeSelectionCard(
                icon: Icons.text_snippet_rounded,
                title: 'Text & Raw Cipher',
                subtitle: 'Preview .txt or decrypt .enc',
                color: kPrimary,
                isSelected: _selectedMode == DecryptMode.textOrEnc,
                onTap: () =>
                    setState(() => _selectedMode = DecryptMode.textOrEnc),
              ),
              const SizedBox(height: 10),
              _ModeSelectionCard(
                icon: Icons.table_view_rounded,
                title: 'CSV Data Export',
                subtitle: 'Converts .enc backup to .csv',
                color: kAmber,
                isSelected: _selectedMode == DecryptMode.csv,
                onTap: () => setState(() => _selectedMode = DecryptMode.csv),
              ),
              const SizedBox(height: 10),
              _ModeSelectionCard(
                icon: Icons.dns_rounded,
                title: 'SQLite Database',
                subtitle: 'Extracts validated .sqlite binary',
                color: kGreen,
                isSelected: _selectedMode == DecryptMode.sqlite,
                onTap: () =>
                    setState(() => _selectedMode = DecryptMode.sqlite),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 3. Dropzone & File Action
        _DropzonePanel(
          mode: _selectedMode,
          stagedFile: _stagedFile,
          isDecrypting: _state == DecryptState.decrypting,
          onSelectFile: _handleFileSelection,
          onRunDecrypt: _runDecryptionPipeline,
        ),

        const SizedBox(height: 18),

        // 4. Security Guarantee
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: kCard.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.verified_user_rounded,
                  size: 16, color: kGreen.withOpacity(0.8)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Zero telemetry: Files are decrypted strictly inside your browser memory.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.45),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Right Output Workbench ────────────────────────────────────────────────

  Widget _buildRightWorkbench() {
    return _Panel(
      padding: EdgeInsets.zero,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _buildWorkbenchContent(),
      ),
    );
  }

  Widget _buildWorkbenchContent() {
    switch (_state) {
      case DecryptState.idle:
        return _buildIdleStateCanvas();
      case DecryptState.decrypting:
        return _buildDecryptingAnimationCanvas();
      case DecryptState.success:
        return _buildSuccessWorkbench();
      case DecryptState.error:
        return _buildErrorCanvas();
    }
  }

  // ─── State 1: Idle Canvas ──────────────────────────────────────────────────

  Widget _buildIdleStateCanvas() {
    return Container(
      key: const ValueKey('idle_canvas'),
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Cybernetic terminal icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(color: kPrimary.withOpacity(0.25)),
              ),
              child: const Icon(
                Icons.terminal_rounded,
                size: 36,
                color: kPrimaryLight,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Awaiting File Input',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                'Select or drop an encrypted file (.enc / .txt) in the left panel to begin instant client-side decryption.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.45),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 36),

            // Quick feature pillars
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FeaturePill(
                  icon: Icons.bolt_rounded,
                  label: 'AES-256 CBC',
                  color: kPrimary,
                ),
                SizedBox(width: 14),
                _FeaturePill(
                  icon: Icons.code_rounded,
                  label: 'JSON Auto-Format',
                  color: kCyan,
                ),
                SizedBox(width: 14),
                _FeaturePill(
                  icon: Icons.download_rounded,
                  label: 'Direct Export',
                  color: kGreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── State 2: Decrypting Animation Canvas ──────────────────────────────────
  // THIS CANNOT FREEZE: Powered by independent radar & cipher ticker animations!

  Widget _buildDecryptingAnimationCanvas() {
    return Container(
      key: const ValueKey('decrypting_canvas'),
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Cybernetic Cryptographic Radar HUD
            SizedBox(
              width: 140,
              height: 140,
              child: AnimatedBuilder(
                animation: Listenable.merge([_radarCtrl, _cipherStreamCtrl]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _CryptoRadarPainter(
                      radarT: _radarCtrl.value,
                      pulseT: _cipherStreamCtrl.value,
                    ),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kPrimary.withOpacity(0.18),
                          border:
                              Border.all(color: kPrimary.withOpacity(0.5)),
                        ),
                        child: const Icon(
                          Icons.lock_open_rounded,
                          color: kPrimaryLight,
                          size: 22,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 32),

            // Dynamic Stage Title
            const Text(
              'Cryptographic Engine Active',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),

            // Real-time Step Text
            Text(
              _currentStepText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kPrimaryLight,
              ),
            ),
            const SizedBox(height: 4),

            // Status message
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.4),
              ),
            ),

            const SizedBox(height: 28),

            // Smooth Progress Bar
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      tween: Tween<double>(
                          begin: 0.0, end: _decryptProgress),
                      builder: (context, val, _) => LinearProgressIndicator(
                        value: val,
                        minHeight: 6,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AES-256 BLOCK DECODE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          color: Colors.white.withOpacity(0.35),
                        ),
                      ),
                      Text(
                        '${(_decryptProgress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kPrimaryLight,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── State 3: Success Studio Workbench ────────────────────────────────────

  Widget _buildSuccessWorkbench() {
    final hasText = _decryptedText.isNotEmpty;
    final lines = hasText ? _decryptedText.split('\n') : <String>[];
    final lineCount = lines.length;
    final charCount = _decryptedText.length;

    return Container(
      key: const ValueKey('success_workbench'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Studio Output Header Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: kBgDark.withOpacity(0.6),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                bottom: BorderSide(color: kBorder.withOpacity(0.8)),
              ),
            ),
            child: Row(
              children: [
                // Success Badge
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: kGreen, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _stagedFile?.name ?? 'Decrypted Output',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_isJson)
                          const _BadgePill(label: 'JSON', color: kCyan)
                        else if (_selectedMode == DecryptMode.csv)
                          const _BadgePill(label: 'CSV TABLE', color: kAmber)
                        else if (_selectedMode == DecryptMode.sqlite)
                          const _BadgePill(label: 'SQLITE 3', color: kGreen)
                        else
                          const _BadgePill(label: 'PLAINTEXT', color: kPrimary),
                      ],
                    ),
                    if (hasText)
                      Text(
                        '$lineCount lines  ·  $charCount characters',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                  ],
                ),
                const Spacer(),

                // Search Bar in Output
                if (hasText)
                  SizedBox(
                    width: 180,
                    height: 34,
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search text…',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 15, color: Colors.white.withOpacity(0.4)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: () => setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                }),
                              )
                            : null,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),

                const SizedBox(width: 10),

                // Copy Button
                if (hasText)
                  _StudioBtn(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onPressed: _copyToClipboard,
                  ),

                const SizedBox(width: 8),

                // Download Button
                _StudioBtn(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  isPrimary: true,
                  onPressed: () async {
                    if (_decryptedBytes != null) {
                      await _downloadFileWeb(
                          _decryptedBytes!, _downloadFileName);
                    } else if (_decryptedText.isNotEmpty) {
                      await _downloadTextFileWeb(
                          _decryptedText, _downloadFileName);
                    }
                  },
                ),

                const SizedBox(width: 8),

                // Clear/Reset Button
                _StudioBtn(
                  icon: Icons.close_rounded,
                  label: '',
                  tooltip: 'Close Output',
                  onPressed: _resetWorkbench,
                ),
              ],
            ),
          ),

          // Main Viewer Canvas
          Expanded(
            child: hasText
                ? _buildTextCodeViewer(lines)
                : _buildBinaryResultViewer(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCodeViewer(List<String> lines) {
    // If searching, filter or highlight
    return Container(
      color: const Color(0xFF070B14),
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 14),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final line = lines[index];
            final lineNumber = index + 1;
            final isMatch = _searchQuery.isNotEmpty &&
                line.toLowerCase().contains(_searchQuery.toLowerCase());

            return Container(
              color: isMatch ? kPrimary.withOpacity(0.18) : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line Number
                  SizedBox(
                    width: 44,
                    child: Text(
                      '$lineNumber',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),

                  // Line Text Content
                  Expanded(
                    child: SelectableText(
                      line.isEmpty ? ' ' : line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: _isJson
                            ? _getJsonLineColor(line)
                            : Colors.white.withOpacity(0.85),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Color _getJsonLineColor(String line) {
    final trimmed = line.trim();
    if (trimmed.startsWith('"') && trimmed.contains('":')) {
      return const Color(0xFFC084FC); // Purple property key
    }
    if (trimmed.startsWith('{') ||
        trimmed.startsWith('}') ||
        trimmed.startsWith('[') ||
        trimmed.startsWith(']')) {
      return Colors.white54;
    }
    if (trimmed.contains(': true') || trimmed.contains(': false')) {
      return kCyan;
    }
    if (trimmed.contains(': null')) {
      return kRed.withOpacity(0.8);
    }
    return Colors.white.withOpacity(0.85);
  }

  Widget _buildBinaryResultViewer() {
    final byteSize = _decryptedBytes?.length ?? 0;
    final mb = (byteSize / 1024 / 1024).toStringAsFixed(2);
    final kb = (byteSize / 1024).toStringAsFixed(1);

    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: kCardElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storage_rounded,
                  color: kGreen, size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'SQLite Database Decrypted',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Header verified: "SQLite format 3". The database is ready for SQLite browser, CLI, or backend inspection.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withOpacity(0.5),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder.withOpacity(0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _downloadFileName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    byteSize > 1048576 ? '$mb MB' : '$kb KB',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: kGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  _downloadFileWeb(_decryptedBytes!, _downloadFileName),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download Decrypted Database'),
              style: FilledButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── State 4: Error Canvas ────────────────────────────────────────────────

  Widget _buildErrorCanvas() {
    return Container(
      key: const ValueKey('error_canvas'),
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kRed.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: kRed.withOpacity(0.3)),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: kRed, size: 40),
            ),
            const SizedBox(height: 22),
            const Text(
              'Decryption Failed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kRed.withOpacity(0.2)),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: Color(0xFFFCA5A5),
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _keyController.text =
                          'ravamate@2025_secure_32bit_key!!';
                      _state = DecryptState.idle;
                    });
                  },
                  icon: const Icon(Icons.key_rounded, size: 16),
                  label: const Text('Reset to Default Key'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: kBorder),
                  ),
                ),
                const SizedBox(width: 14),
                FilledButton.icon(
                  onPressed: _runDecryptionPipeline,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry Decryption'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Help Dialog ──────────────────────────────────────────────────────────

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _IconBadge(
                      icon: Icons.menu_book_rounded, color: kPrimary),
                  const SizedBox(width: 12),
                  const Text('Cryptographic Specifications',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  const Spacer(),
                  _IconBtn(
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _HelpStepRow(
                n: '1',
                title: 'Master Key Configuration',
                desc:
                    'AES-256 requires a 32-character (256-bit) UTF-8 key. Both sender and decryptor must share this exact key.',
              ),
              const SizedBox(height: 14),
              const _HelpStepRow(
                n: '2',
                title: '16-Byte Prefix IV (CBC Mode)',
                desc:
                    'Cipher files are expected to have the 16-byte initialization vector prefixed directly before the ciphertext payload.',
              ),
              const SizedBox(height: 14),
              const _HelpStepRow(
                n: '3',
                title: 'Text / JSON / Generic (.enc & .txt)',
                desc:
                    'For .txt files, results render directly inside the code editor workbench. For .enc files, the decrypted text is previewed and automatically saved.',
              ),
              const SizedBox(height: 14),
              const _HelpStepRow(
                n: '4',
                title: 'CSV & SQLite Backups',
                desc:
                    'Specialized pipelines convert encrypted JSON arrays into formatted CSV spreadsheets or extract raw SQLite 3 binaries.',
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Dismiss',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dropzone & Action Panel ────────────────────────────────────────────────

class _DropzonePanel extends StatefulWidget {
  final DecryptMode mode;
  final PlatformFile? stagedFile;
  final bool isDecrypting;
  final VoidCallback onSelectFile;
  final VoidCallback onRunDecrypt;

  const _DropzonePanel({
    required this.mode,
    required this.stagedFile,
    required this.isDecrypting,
    required this.onSelectFile,
    required this.onRunDecrypt,
  });

  @override
  State<_DropzonePanel> createState() => _DropzonePanelState();
}

class _DropzonePanelState extends State<_DropzonePanel> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hasFile = widget.stagedFile != null;
    final file = widget.stagedFile;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _IconBadge(
                icon: Icons.upload_file_rounded,
                color: kPrimaryLight,
              ),
              const SizedBox(width: 12),
              const Text(
                'File Input Station',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (hasFile)
                const _BadgePill(
                  label: 'FILE STAGED',
                  color: kGreen,
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive Dropzone Box
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.isDecrypting ? null : widget.onSelectFile,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? kPrimary.withOpacity(0.08)
                      : Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isHovered
                        ? kPrimary
                        : (hasFile ? kGreen.withOpacity(0.6) : kBorder),
                    width: _isHovered || hasFile ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      hasFile
                          ? Icons.task_alt_rounded
                          : Icons.cloud_upload_outlined,
                      size: 38,
                      color: hasFile
                          ? kGreen
                          : (_isHovered ? kPrimaryLight : Colors.white38),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasFile
                          ? file!.name
                          : 'Click to select or drop your file',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasFile ? Colors.white : Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile
                          ? '${(file!.size / 1024).toStringAsFixed(1)} KB  ·  Click to change file'
                          : 'Supported: ${_modeSupportedExtensions(widget.mode)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Primary Decrypt Action Button
          FilledButton(
            onPressed: (widget.isDecrypting || !hasFile)
                ? (hasFile ? null : widget.onSelectFile)
                : widget.onRunDecrypt,
            style: FilledButton.styleFrom(
              backgroundColor: kPrimary,
              disabledBackgroundColor: kPrimary.withOpacity(0.3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
            ),
            child: widget.isDecrypting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Decrypting...',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        hasFile
                            ? Icons.lock_open_rounded
                            : Icons.file_open_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasFile
                            ? 'Run AES-256 Decryption'
                            : 'Select File to Decrypt',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _modeSupportedExtensions(DecryptMode mode) {
    switch (mode) {
      case DecryptMode.textOrEnc:
        return '.enc, .txt';
      case DecryptMode.csv:
        return '.enc (JSON/CSV backup)';
      case DecryptMode.sqlite:
        return '.enc (SQLite database)';
    }
  }
}

// ─── Mode Selection Card ────────────────────────────────────────────────────

class _ModeSelectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeSelectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.12)
              : Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : kBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(isSelected ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.radio_button_checked_rounded, color: color, size: 18)
            else
              const Icon(Icons.radio_button_off_rounded,
                  color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Cryptographic Radar Custom Painter (Decryption HUD) ────────────────────

class _CryptoRadarPainter extends CustomPainter {
  final double radarT;
  final double pulseT;

  _CryptoRadarPainter({required this.radarT, required this.pulseT});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Outer faint ring
    final faintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = kPrimary.withOpacity(0.2);
    canvas.drawCircle(center, maxR, faintPaint);
    canvas.drawCircle(center, maxR * 0.7, faintPaint);
    canvas.drawCircle(center, maxR * 0.4, faintPaint);

    // Expanding pulse wave
    final waveR = maxR * pulseT;
    final waveOpacity = (1.0 - pulseT).clamp(0.0, 1.0);
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = kCyan.withOpacity(waveOpacity * 0.5);
    canvas.drawCircle(center, waveR, wavePaint);

    // Rotating sweep sector
    const sweepAngle = math.pi * 0.6;
    final startAngle = radarT * 2 * math.pi;

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweepAngle,
        colors: [
          kPrimary.withOpacity(0.0),
          kPrimary.withOpacity(0.35),
        ],
        transform: GradientRotation(startAngle),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR),
      startAngle,
      sweepAngle,
      true,
      sweepPaint,
    );

    // Crosshairs
    final crossHairPaint = Paint()
      ..color = kPrimary.withOpacity(0.15)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - maxR, center.dy),
        Offset(center.dx + maxR, center.dy), crossHairPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxR),
        Offset(center.dx, center.dy + maxR), crossHairPaint);
  }

  @override
  bool shouldRepaint(_CryptoRadarPainter old) =>
      old.radarT != radarT || old.pulseT != pulseT;
}

// ─── Animated Background ─────────────────────────────────────────────────────

class _AnimatedBackground extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedBackground({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => SizedBox.expand(
        child: CustomPaint(painter: _BgPainter(controller.value)),
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  final double t;
  const _BgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Solid base dark gradient
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF080C16), Color(0xFF090E1A), Color(0xFF04060C)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final w = size.width;
    final h = size.height;

    // Glowing cyber orbs that drift gently
    _orb(canvas, Offset(w * (0.10 + t * 0.08), h * (0.15 + t * 0.05)),
        w * 0.32, kPrimary.withOpacity(0.12));
    _orb(canvas, Offset(w * (0.85 - t * 0.07), h * (0.75 + t * 0.06)),
        w * 0.28, kIndigo.withOpacity(0.10));
    _orb(canvas, Offset(w * 0.5, h * (0.5 + math.sin(t * math.pi) * 0.04)),
        w * 0.20, kCyan.withOpacity(0.05));
  }

  void _orb(Canvas canvas, Offset center, double r, Color color) {
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withOpacity(0)],
        ).createShader(Rect.fromCircle(center: center, radius: r))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 90),
    );
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.t != t;
}

// ─── Reusable UI Building Blocks ─────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _Panel({
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard.withOpacity(0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color color;
  const _BadgePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isValid;
  final int length;
  const _StatusPill({required this.isValid, required this.length});

  @override
  Widget build(BuildContext context) {
    final color = isValid ? kGreen : kAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isValid
                ? Icons.verified_rounded
                : Icons.warning_amber_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            isValid ? '32/32 Valid' : '$length/32 Chars',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const _IconBtn({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white54, size: 16),
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _HeaderBtn({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
  final String? tooltip;

  const _StudioBtn({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 8 : 12, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? kPrimary : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPrimary ? kPrimary : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: isPrimary ? Colors.white : Colors.white70),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPrimary ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _HelpStepRow extends StatelessWidget {
  final String n;
  final String title;
  final String desc;

  const _HelpStepRow({
    required this.n,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimary, kIndigo],
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              n,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Desktop Web Toast Notification Card ─────────────────────────────────────

class _WebToast {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final DateTime timestamp;

  _WebToast({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
  }) : timestamp = DateTime.now();
}

class _WebToastCard extends StatefulWidget {
  final _WebToast toast;
  final VoidCallback onDismiss;

  const _WebToastCard({
    super.key,
    required this.toast,
    required this.onDismiss,
  });

  @override
  State<_WebToastCard> createState() => _WebToastCardState();
}

class _WebToastCardState extends State<_WebToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _timerController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..forward();
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.toast;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.color.withOpacity(0.35), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: t.color.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: t.color.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: t.color.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(t.icon, color: t.color, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          t.message,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withOpacity(0.65),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: widget.onDismiss,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _timerController,
              builder: (context, _) => LinearProgressIndicator(
                value: 1.0 - _timerController.value,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  t.color.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
