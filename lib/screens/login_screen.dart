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

  static const String _baseUrl =
      'https://hwc-backend-fixed.onrender.com';

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isCreateAccount = false;
  bool _otpSent = false;
  bool _loading = false;
  bool _accountCreated = false;

  String _errorMsg = '';
  String? _savedEmail;
  String? _savedUsername;

  @override
  void initState() {
    super.initState();
    _loadSavedAccount();
  }

  Future<void> _loadSavedAccount() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _savedEmail = prefs.getString('wildora_email');
      _savedUsername = prefs.getString('wildora_username');
      _accountCreated =
          prefs.getBool('wildora_account_created') ?? false;

      if (_savedEmail != null && _savedEmail!.isNotEmpty) {
        _emailController.text = _savedEmail!;
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _switchMode(bool createAccount) {
    if (_loading) return;

    setState(() {
      _isCreateAccount = createAccount;
      _otpSent = false;
      _otpController.clear();
      _errorMsg = '';

      if (createAccount) {
        // Always start a fresh registration form.
        // A previously saved account must NOT block
        // creation of another account.
        _usernameController.clear();
        _emailController.clear();
      } else if (_savedEmail != null &&
          _savedEmail!.isNotEmpty) {
        // Login may conveniently use the last saved email.
        _emailController.text = _savedEmail!;
      }
    });
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _errorMsg = 'Please enter your email address.';
      });
      return;
    }

    if (!RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email)) {
      setState(() {
        _errorMsg = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/send-otp'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _otpSent = true;
          _errorMsg = '';
        });
      } else {
        String message = 'Failed to send OTP.';

        try {
          final data = jsonDecode(response.body);

          if (data is Map && data['message'] != null) {
            message = data['message'].toString();
          } else if (data is Map && data['error'] != null) {
            message = data['error'].toString();
          }
        } catch (_) {}

        setState(() {
          _errorMsg = message;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg =
            'Unable to connect to server. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      setState(() {
        _errorMsg = 'Please enter the 6-digit OTP.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/verify-otp'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'otp': otp,
        }),
      );

      if (response.statusCode == 200) {
        await _handleSuccessfulVerification();
      } else {
        String message = 'Invalid OTP. Please try again.';

        try {
          final data = jsonDecode(response.body);

          if (data is Map && data['message'] != null) {
            message = data['message'].toString();
          } else if (data is Map && data['error'] != null) {
            message = data['error'].toString();
          }
        } catch (_) {}

        setState(() {
          _errorMsg = message;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg =
            'Unable to connect to server. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleSuccessfulVerification() async {
    final email = _emailController.text.trim();

    if (_isCreateAccount) {
      final username = _usernameController.text.trim();

      if (username.isEmpty) {
        setState(() {
          _errorMsg = 'Please enter a username.';
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        'wildora_username',
        username,
      );

      await prefs.setString(
        'wildora_email',
        email,
      );

      await prefs.setBool(
        'wildora_account_created',
        true,
      );

      _savedEmail = email;
      _savedUsername = username;
      _accountCreated = true;

      if (!mounted) return;

      setState(() {
        _errorMsg = '';
      });

      await _showSuccessDialog(
        'Account created successfully!',
        'Your WILDORA account has been created. '
            'You can now log in using your email.',
      );

      if (!mounted) return;

      setState(() {
        _isCreateAccount = false;
        _otpSent = false;
        _otpController.clear();
        _usernameController.clear();
        _emailController.text = email;
      });
    } else {
      await _loginUser();
    }
  }

  Future<void> _loginUser() async {
    final email = _emailController.text.trim();

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        'wildora_email',
        email,
      );

      await prefs.setBool(
        'wildora_logged_in',
        true,
      );

      _savedEmail = email;

      if (!mounted) return;

      await _showSuccessDialog(
        'Login successful!',
        'Welcome back to WILDORA.',
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMsg =
            'Login failed. Please try again.';
      });
    }
  }

  Future<void> _createAccount() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _errorMsg = 'Please enter a username.';
      });
      return;
    }

    if (email.isEmpty) {
      setState(() {
        _errorMsg = 'Please enter your email address.';
      });
      return;
    }

    if (!RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email)) {
      setState(() {
        _errorMsg = 'Please enter a valid email address.';
      });
      return;
    }

    await _sendOtp();
  }

  Future<void> _showSuccessDialog(
    String title,
    String message,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cream,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: forestDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: ink,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(
                  color: leaf,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: leaf,
      ),
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(
        color: muted,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: leaf,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Colors.red,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: Colors.red,
          width: 2,
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: forest,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: forest.withOpacity(0.25),
                blurRadius: 15,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: const Icon(
            Icons.eco,
            color: leafLight,
            size: 48,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'WILDORA',
          style: TextStyle(
            color: forestDark,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'WILDLIFE • PREDICTION',
          style: TextStyle(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _switchMode(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: !_isCreateAccount
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: !_isCreateAccount
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Sign In',
                    style: TextStyle(
                      color: !_isCreateAccount
                          ? forest
                          : muted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _switchMode(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _isCreateAccount
                      ? Colors.white
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: _isCreateAccount
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Create Account',
                    style: TextStyle(
                      color: _isCreateAccount
                          ? forest
                          : muted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateAccountForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _usernameController,
          textInputAction: TextInputAction.next,
          decoration: _inputDecoration(
            'Username',
            Icons.person_outline,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          decoration: _inputDecoration(
            'Email Address',
            Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 20),
        _buildPrimaryButton(
          text: _otpSent
              ? 'VERIFY OTP'
              : 'CREATE ACCOUNT',
          onPressed: _otpSent
              ? _verifyOtp
              : _createAccount,
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          decoration: _inputDecoration(
            'Email Address',
            Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 20),
        _buildPrimaryButton(
          text: _otpSent
              ? 'VERIFY OTP'
              : 'SEND OTP',
          onPressed: _otpSent
              ? _verifyOtp
              : _sendOtp,
        ),
      ],
    );
  }

  Widget _buildOtpSection() {
    if (!_otpSent) {
      return const SizedBox.shrink();
    }

    final defaultPinTheme = PinTheme(
      width: 48,
      height: 54,
      textStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: forestDark,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: leaf,
          width: 2,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        const Text(
          'Enter the 6-digit OTP sent to your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: muted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Pinput(
            controller: _otpController,
            length: 6,
            defaultPinTheme: defaultPinTheme,
            focusedPinTheme: focusedPinTheme,
            keyboardType: TextInputType.number,
            onCompleted: (_) {
              _verifyOtp();
            },
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: _loading ? null : _sendOtp,
          child: const Text(
            'Resend OTP',
            style: TextStyle(
              color: leaf,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: _loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: forest,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              forest.withOpacity(0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(
                    Colors.white,
                  ),
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }

  Widget _buildError() {
    if (_errorMsg.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.red.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red.shade700,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _errorMsg,
              style: TextStyle(
                color: Colors.red.shade800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedAccountInfo() {
    if (_savedEmail == null ||
        _savedEmail!.isEmpty ||
        _isCreateAccount) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: leafLight.withOpacity(0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: leaf.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: forest,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                if (_savedUsername != null &&
                    _savedUsername!.isNotEmpty)
                  Text(
                    _savedUsername!,
                    style: const TextStyle(
                      color: forestDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  _savedEmail!,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 30,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 470,
              ),
              child: Column(
                children: [
                  _buildLogo(),
                  const SizedBox(height: 30),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withOpacity(0.07),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        _buildModeSelector(),
                        const SizedBox(height: 24),
                        _buildSavedAccountInfo(),
                        if (_isCreateAccount)
                          _buildCreateAccountForm()
                        else
                          _buildLoginForm(),
                        _buildOtpSection(),
                        _buildError(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Protecting wildlife • Predicting conflict • '
                    'Building a safer future',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
