import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color forest = Color(0xFF123D28);
  static const Color forestDark = Color(0xFF082217);
  static const Color leaf = Color(0xFF2F8F4E);
  static const Color leafLight = Color(0xFFB8D98C);
  static const Color cream = Color(0xFFF7F5EE);
  static const Color ink = Color(0xFF17231C);
  static const Color muted = Color(0xFF708076);

  static const String _baseUrl = 'https://hwc-backend-fixed.onrender.com';

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isCreateAccount = false;
  bool _otpSent = false;
  bool _loading = false;
  String _errorMsg = '';
  String? _savedEmail;
  String? _savedUsername;
  bool _accountCreated = false;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
  }

  Future<void> _loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedEmail = prefs.getString('wildora_email');
    final savedUsername = prefs.getString('wildora_username');
    final accountCreated = prefs.getBool('wildora_account_created') ??
        (savedEmail != null && savedEmail.isNotEmpty);

    if (!mounted) return;
    setState(() {
      _savedEmail = savedEmail;
      _savedUsername = savedUsername;
      _accountCreated = accountCreated;
      // First launch -> Create Account. Existing account -> Login.
      _isCreateAccount = !accountCreated;
      if (accountCreated && savedEmail != null) {
        _emailController.text = savedEmail;
      }
    });
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w.\-]+@[\w\-]+\.[\w.\-]+$').hasMatch(email);

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _switchMode(bool createAccount) {
    if (_loading) return;
    if (createAccount && _accountCreated) {
      setState(() {
        _isCreateAccount = false;
        _otpSent = false;
        _otpController.clear();
        _errorMsg = 'An account is already saved on this device. Please log in.';
        if (_savedEmail != null) _emailController.text = _savedEmail!;
      });
      return;
    }
    setState(() {
      _isCreateAccount = createAccount;
      _otpSent = false;
      _otpController.clear();
      _errorMsg = '';
    });
  }

  Future<void> _sendOTP() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();

    if (_isCreateAccount && username.length < 2) {
      setState(() => _errorMsg = 'Please enter your username');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _errorMsg = 'Please enter a valid email address');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = '';
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/send-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'purpose': _isCreateAccount ? 'create' : 'login',
              'username': _isCreateAccount ? username : null,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && body['error'] == null) {
        setState(() {
          _loading = false;
          _otpSent = true;
        });
      } else {
        setState(() {
          _loading = false;
          _errorMsg = body['error'] ?? 'Could not send OTP. Please try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Network error. Please check your connection and try again.';
      });
    }
  }

  Future<void> _verifyOTP() async {
    final otp = _otpController.text.trim();
    final email = _emailController.text.trim();

    if (otp.length != 6) {
      setState(() => _errorMsg = 'Please enter the 6-digit OTP');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = '';
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'otp': otp,
              'purpose': _isCreateAccount ? 'create' : 'login',
              'username': _isCreateAccount ? _usernameController.text.trim() : null,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && body['error'] == null) {
        final prefs = await SharedPreferences.getInstance();

        if (_isCreateAccount) {
          // Account creation: save the profile, then require a normal login.
          final username = _usernameController.text.trim();
          await prefs.setString('wildora_username', username);
          await prefs.setString('wildora_email', email);
          await prefs.setBool('wildora_account_created', true);
          // Creating an account only verifies/saves the profile. It does not log in.
          await FirebaseAuth.instance.signOut();

          setState(() {
            _savedUsername = username;
            _savedEmail = email;
            _accountCreated = true;
            _isCreateAccount = false;
            _emailController.text = email;
            _otpSent = false;
            _otpController.clear();
            _usernameController.clear();
            _loading = false;
            _errorMsg = 'Account created successfully. Now sign in with your email.';
          });
        } else {
          // Existing account login: trust the backend's persistent account record,
          // not a device-local flag. This allows login from another device/browser.
          final account = body['account'];
          final username = account is Map ? account['username']?.toString() : null;
          final normalizedEmail = account is Map && account['email'] != null
              ? account['email'].toString()
              : email;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('wildora_email', normalizedEmail);
          if (username != null && username.isNotEmpty) {
            await prefs.setString('wildora_username', username);
          }
          await prefs.setBool('wildora_account_created', true);

          final credential = await FirebaseAuth.instance.signInAnonymously();
          if (username != null && username.isNotEmpty) {
            await credential.user?.updateDisplayName(username);
          }
          if (!mounted) return;
          setState(() {
            _savedEmail = normalizedEmail;
            _savedUsername = username;
            _accountCreated = true;
            _loading = false;
          });
        }
      } else {
        setState(() {
          _loading = false;
          _errorMsg = body['error'] ?? 'Invalid OTP. Please try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Network error. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: forestDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/wildora_login_background.png',
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withOpacity(.42)),
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;
              return SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 54 : 20,
                    vertical: isDesktop ? 34 : 22,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - (isDesktop ? 68 : 44)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.forest_rounded, color: Colors.white, size: 34),
                            SizedBox(width: 10),
                            Text('WILDORA', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2.5)),
                          ],
                        ),
                        SizedBox(height: isDesktop ? 65 : 35),
                        if (isDesktop)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: 50),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('SMART WILDLIFE • SAFER COMMUNITIES', style: TextStyle(color: Color(0xFFE1F2D7), fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                                      SizedBox(height: 18),
                                      Text(
                                        'Predict wildlife risk\n'
                                        'before it becomes a problem.',
                                        style: TextStyle(color: Colors.white, fontSize: 42, height: 1.12, fontWeight: FontWeight.w900),
                                      ),
                                      SizedBox(height: 18),
                                      Text('Use location intelligence, ML prediction and community reports to make safer decisions around wildlife-sensitive areas.', style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 16, height: 1.55)),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: 500, child: _authCard()),
                            ],
                          )
                        else ...[
                          const Text('SMART WILDLIFE • SAFER COMMUNITIES', style: TextStyle(color: Color(0xFFE1F2D7), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          const Text('Predict wildlife risk before it becomes a problem.', style: TextStyle(color: Colors.white, fontSize: 28, height: 1.15, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 24),
                          _authCard(),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _topBrandMark({required bool showName}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [
              BoxShadow(blurRadius: 12, offset: Offset(0, 5), color: Color(0x22000000)),
            ],
          ),
          child: const Icon(Icons.forest_rounded, color: leaf, size: 24),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          const Text(
            'WILDORA',
            style: TextStyle(
              color: forestDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
            ),
          ),
        ],
      ],
    );
  }

  Widget _brandPanel() {
    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [forestDark, forest, Color(0xFF1D633B)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=1600&q=85',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [forestDark.withOpacity(.94), forest.withOpacity(.78), const Color(0xFF1D633B).withOpacity(.86)],
                ),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _ForestPatternPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(76, 92, 70, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Text(
                    'SMART WILDLIFE • SAFER COMMUNITIES',
                    style: TextStyle(
                      color: leafLight,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'WILDORA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    height: 0.98,
                  ),
                ),
                const SizedBox(height: 10),
                const SizedBox(height: 4),
                const SizedBox(
                  width: 500,
                  child: Text(
                    'A smarter way to understand wildlife risk and help people live safely alongside nature.',
                    style: TextStyle(
                      color: Color(0xD9FFFFFF),
                      fontSize: 19,
                      height: 1.55,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 38),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: const [
                    _TrustPill(icon: Icons.radar_rounded, text: 'Risk prediction'),
                    _TrustPill(icon: Icons.location_on_rounded, text: 'Live location'),
                    _TrustPill(icon: Icons.notifications_active_rounded, text: 'Early alerts'),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.eco_rounded, color: leafLight),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'Protect wildlife. Protect communities. Make every journey safer.',
                        style: TextStyle(color: Color(0xCCFFFFFF), height: 1.45, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileBrandHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 78, 28, 34),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(
                'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=1200&q=85',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: forestDark),
              ),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(color: forestDark.withOpacity(.68)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: const [
                Icon(Icons.forest_rounded, color: Colors.white, size: 54),
                SizedBox(height: 12),
                Text(
                  'WILDORA',
                  style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 2.5),
                ),
                SizedBox(height: 8),
                Text(
                  'Smart wildlife risk • Safer communities',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _authArea() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 620),
      padding: const EdgeInsets.fromLTRB(34, 54, 34, 42),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: _authCard(),
        ),
      ),
    );
  }

  Widget _authCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_otpSent) ...[
              const Text(
                'Welcome to WILDORA',
                style: TextStyle(color: ink, fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                _isCreateAccount
                    ? 'Create your account and start exploring wildlife risk insights.'
                    : 'Sign in securely using a one-time code sent to your email.',
                style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              _modeSwitch(),
              const SizedBox(height: 26),
              if (_isCreateAccount) ...[
                _fieldLabel('Username'),
                const SizedBox(height: 8),
                _textField(
                  controller: _usernameController,
                  hint: 'Username',
                  icon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),
              ],
              _fieldLabel('Email address'),
              const SizedBox(height: 8),
              _textField(
                controller: _emailController,
                hint: 'you@example.com',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _sendOTP(),
              ),
              const SizedBox(height: 20),
              _primaryButton(
                label: _isCreateAccount ? 'Create account & send OTP' : 'Send OTP & sign in',
                icon: Icons.arrow_forward_rounded,
                onPressed: _loading ? null : _sendOTP,
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'No password needed • OTP is sent to your email',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                ),
              ),
            ] else ...[
              _otpHeader(),
              const SizedBox(height: 24),
              _fieldLabel('6-digit verification code'),
              const SizedBox(height: 12),
              Center(child: _otpInput()),
              const SizedBox(height: 22),
              _primaryButton(
                label: _isCreateAccount ? 'Verify & create account' : 'Verify & sign in',
                icon: Icons.verified_rounded,
                onPressed: _loading ? null : _verifyOTP,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _otpSent = false;
                              _otpController.clear();
                              _errorMsg = '';
                            }),
                    child: const Text('Change email'),
                  ),
                  const Text('•', style: TextStyle(color: muted)),
                  TextButton(
                    onPressed: _loading ? null : _sendOTP,
                    child: const Text('Resend OTP'),
                  ),
                ],
              ),
            ],
            if (_errorMsg.isNotEmpty) ...[
              const SizedBox(height: 14),
              _errorBox(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modeSwitch() {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F0),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(child: _modeButton('Sign in', false)),
          Expanded(child: _modeButton('Create account', true)),
        ],
      ),
    );
  }

  Widget _modeButton(String text, bool create) {
    final selected = _isCreateAccount == create;
    return GestureDetector(
      onTap: () => _switchMode(create),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 2))]
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? forest : muted,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _otpHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F3E9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.mark_email_read_outlined, color: leaf, size: 27),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Check your email',
                style: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                'We sent a 6-digit OTP to\n${_emailController.text.trim()}',
                style: const TextStyle(color: muted, fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _otpInput() {
    final pinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: const TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w800),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F5),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFDCE4DD)),
      ),
    );

    return Pinput(
      controller: _otpController,
      length: 6,
      keyboardType: TextInputType.number,
      defaultPinTheme: pinTheme,
      focusedPinTheme: pinTheme.copyWith(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: leaf, width: 2),
        ),
      ),
      submittedPinTheme: pinTheme.copyWith(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F7F0),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: leaf),
        ),
      ),
      onCompleted: (_) {
        if (!_loading) _verifyOTP();
      },
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w800),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9AA69E), fontSize: 14),
        prefixIcon: Icon(icon, color: const Color(0xFF7B8B81), size: 21),
        filled: true,
        fillColor: const Color(0xFFF7F9F6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E7E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E7E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: leaf, width: 1.8),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: _loading
            ? const SizedBox.shrink()
            : Icon(icon, size: 19),
        label: _loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: forest,
          foregroundColor: Colors.white,
          disabledBackgroundColor: forest.withValues(alpha: 0.65),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _errorBox() {
    final success = _errorMsg.toLowerCase().contains('account created');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFEAF7EC) : const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: success ? const Color(0xFFB8DDBD) : const Color(0xFFFFD4D0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: success ? const Color(0xFF2E7D32) : const Color(0xFFD94841),
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _errorMsg,
              style: TextStyle(
                color: success ? const Color(0xFF21662A) : const Color(0xFFB3261E),
                fontSize: 12.5,
                height: 1.4,
                fontWeight: success ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TrustPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Color(0xFFB8D98C), size: 16),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ForestPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final treePaint = Paint()..color = Colors.white.withValues(alpha: 0.045);
    final softPaint = Paint()..color = const Color(0xFFB8D98C).withValues(alpha: 0.035);

    for (int i = 0; i < 13; i++) {
      final x = (i * 113.0) % (size.width + 120) - 60;
      final baseY = size.height - 50 - ((i % 4) * 12);
      _drawTree(canvas, Offset(x, baseY), 80 + (i % 3) * 22, treePaint);
    }

    for (int i = 0; i < 9; i++) {
      final x = 50.0 + i * 155;
      final y = 100.0 + (i % 3) * 120;
      canvas.drawCircle(Offset(x, y), 80 + (i % 2) * 30, softPaint);
    }
  }

  void _drawTree(Canvas canvas, Offset base, double height, Paint paint) {
    final trunk = Path()
      ..moveTo(base.dx - height * 0.055, base.dy)
      ..lineTo(base.dx + height * 0.055, base.dy)
      ..lineTo(base.dx + height * 0.04, base.dy - height * 0.33)
      ..lineTo(base.dx - height * 0.04, base.dy - height * 0.33)
      ..close();
    canvas.drawPath(trunk, paint);

    for (int i = 0; i < 3; i++) {
      final center = Offset(base.dx, base.dy - height * (0.28 + i * 0.2));
      final width = height * (0.58 - i * 0.09);
      final top = center.dy - height * 0.25;
      final path = Path()
        ..moveTo(center.dx, top)
        ..lineTo(center.dx - width / 2, center.dy + height * 0.16)
        ..lineTo(center.dx + width / 2, center.dy + height * 0.16)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
