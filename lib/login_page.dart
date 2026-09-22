import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'auth_service.dart';

const Color kPrimary = Color(0xFF8B5CF6);
const Color kPrimaryLight = Color(0xFFA78BFA);
const Color kIndigo = Color(0xFF6366F1);
const Color kCyan = Color(0xFF06B6D4);
const Color kGreen = Color(0xFF10B981);
const Color kRed = Color(0xFFEF4444);

const Color kBgDark = Color(0xFF090D16);
const Color kCard = Color(0xFF131D33);
const Color kBorder = Color(0xFF1E2E4A);

class StudioLoginPage extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const StudioLoginPage({super.key, required this.onAuthenticated});

  @override
  State<StudioLoginPage> createState() => _StudioLoginPageState();
}

class _StudioLoginPageState extends State<StudioLoginPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final FocusNode _userFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

  bool _obscurePass = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _userController.dispose();
    _passController.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final user = _userController.text.trim();
    final pass = _passController.text.trim();

    if (user.isEmpty || pass.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both operator ID and security passkey.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Small async delay for smooth UI transition
    await Future.delayed(const Duration(milliseconds: 320));

    final success = AuthService().login(
      username: user,
      passkey: pass,
      rememberMe: _rememberMe,
    );

    if (!mounted) return;

    if (success) {
      widget.onAuthenticated();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Access Denied: Invalid operator username or security passkey.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      body: Stack(
        children: [
          // Cyber glowing background
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _bgCtrl,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _LoginBgPainter(_bgCtrl.value),
              ),
            ),
          ),

          // Center login card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  decoration: BoxDecoration(
                    color: kCard.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: kPrimary.withOpacity(0.3),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.55),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: kPrimary.withOpacity(0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header accent line
                      Container(
                        height: 3,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [kPrimary, kIndigo, kCyan],
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Shield Logo
                            Center(
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [kPrimary, kIndigo],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimary.withOpacity(0.4),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.shield_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Titles
                            const Center(
                              child: Text(
                                'FDC Decryptor Studio',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: Text(
                                'Operator Authentication & Session Gateway',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white.withOpacity(0.45),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Error Message Banner
                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: kRed.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: kRed.withOpacity(0.35),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded,
                                        color: kRed, size: 16),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                          color: Color(0xFFFCA5A5),
                                          fontSize: 12,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],

                            // Username field
                            Text(
                              'OPERATOR ID',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _userController,
                              focusNode: _userFocus,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13.5),
                              decoration: InputDecoration(
                                hintText: 'Enter operator username…',
                                prefixIcon: Icon(
                                  Icons.person_outline_rounded,
                                  color: kPrimary.withOpacity(0.7),
                                  size: 19,
                                ),
                              ),
                              onSubmitted: (_) => _passFocus.requestFocus(),
                            ),
                            const SizedBox(height: 18),

                            // Password field
                            Text(
                              'SECURITY PASSKEY',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _passController,
                              focusNode: _passFocus,
                              obscureText: _obscurePass,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter security passkey…',
                                prefixIcon: Icon(
                                  Icons.lock_outline_rounded,
                                  color: kPrimary.withOpacity(0.7),
                                  size: 19,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePass
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                    size: 18,
                                    color: Colors.white38,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscurePass = !_obscurePass),
                                ),
                              ),
                              onSubmitted: (_) => _handleLogin(),
                            ),
                            const SizedBox(height: 14),

                            // Remember Me & Session Duration
                            Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: kPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (val) => setState(
                                        () => _rememberMe = val ?? false),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => setState(
                                      () => _rememberMe = !_rememberMe),
                                  child: Text(
                                    'Remember session (24 hours)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.65),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Unlock Button
                            FilledButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: FilledButton.styleFrom(
                                backgroundColor: kPrimary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                              ),
                              child: _isLoading
                                  ? const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Authenticating Session...',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.lock_open_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'Unlock Studio Session',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 24),

                            // Security Badges Footer
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _LoginBadge(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'AES-256 Engine',
                                  color: kGreen,
                                ),
                                SizedBox(width: 10),
                                _LoginBadge(
                                  icon: Icons.timer_outlined,
                                  label: 'Inactivity Guard',
                                  color: kCyan,
                                ),
                                SizedBox(width: 10),
                                _LoginBadge(
                                  icon: Icons.memory_rounded,
                                  label: 'Local Sandbox',
                                  color: kPrimary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _LoginBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withOpacity(0.4),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LoginBgPainter extends CustomPainter {
  final double t;
  const _LoginBgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF070A13), Color(0xFF090E1B), Color(0xFF03050A)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final w = size.width;
    final h = size.height;

    _orb(canvas, Offset(w * 0.25, h * (0.2 + t * 0.05)), w * 0.35,
        kPrimary.withOpacity(0.14));
    _orb(canvas, Offset(w * 0.75, h * (0.8 - t * 0.06)), w * 0.30,
        kIndigo.withOpacity(0.12));
    _orb(canvas, Offset(w * (0.5 + math.sin(t * math.pi) * 0.04), h * 0.5),
        w * 0.22, kCyan.withOpacity(0.06));
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
  bool shouldRepaint(_LoginBgPainter old) => old.t != t;
}
