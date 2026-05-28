import 'dart:ui';
import 'package:aimcamila/pages/login_page/auth_manager.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  // Controladores nativos (más limpio que usar un Model externo para una sola página)
  late TabController _tabController;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _createEmailController = TextEditingController();
  final TextEditingController _createPasswordController =
      TextEditingController();

  late AuthManager _authManager;
  final _formKeySignIn = GlobalKey<FormState>();
  final _formKeySignUp = GlobalKey<FormState>();

  bool _isPasswordVisible = false;
  bool _isCreatePasswordVisible = false;

  // Animación para el fondo
  late AnimationController _animController;
  late Animation<Offset> _animOffset;

  @override
  void initState() {
    super.initState();
    _authManager = AuthManager();
    _tabController = TabController(length: 2, vsync: this);

    // Animación suave de "respiración" para el fondo
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _animOffset = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: const Offset(0, -0.05),
    ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _createEmailController.dispose();
    _createPasswordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveUserPreferences(bool isLoggedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
    await prefs.setString(
        'initialPage', 'CamilaPage'); // Forzamos CamilaPage por defecto
  }

  // --- UI Helpers ---
  void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Paleta de colores moderna "Cyber-Camila"
    final bgColor = const Color(0xFF0F111A); // Casi negro
    final primaryColor =
        const Color.fromARGB(255, 62, 29, 105); // Violeta oscuro
    final tabBarColor = const Color(0xFF6C63FF); // Violeta eléctrico
    final secondaryColor = const Color(0xFF1A0B2E); // Cyan neón

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // 1. Fondo Animado (Orbes)
          Positioned(
            top: -100,
            right: -50,
            child: SlideTransition(
              position: _animOffset,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor.withValues(alpha: 0.4),
                  boxShadow: [BoxShadow(color: primaryColor, blurRadius: 100)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: SlideTransition(
              position: _animOffset,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: secondaryColor.withValues(alpha: 0.3),
                  boxShadow: [
                    BoxShadow(color: secondaryColor, blurRadius: 100)
                  ],
                ),
              ),
            ),
          ),

          // 2. Efecto Glassmorphism Global
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withValues(alpha: 0.2)),
          ),

          // 3. Contenido Principal
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo / Título
                  Text(
                    "AI'm Camila",
                    style: GoogleFonts.dancingScript(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  // ----------------------------------------------
                  const SizedBox(height: 8),
                  Text(
                    "Try not to bore me.", // Sarcasmo de Camila
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Tarjeta de Login (Glass Card)
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 500),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05), // Muy sutil
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: [
                        // Tabs personalizados
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: TabBar(
                              // --- MAGIA 1: Apaga la línea gris pegada de Material 3 ---
                              dividerColor: Colors.transparent,

                              controller: _tabController,
                              indicator: BoxDecoration(
                                color: tabBarColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.white60,
                              labelStyle: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600, fontSize: 16),
                              indicatorSize: TabBarIndicatorSize.tab,
                              tabs: const [
                                Tab(text: "Sign In"),
                                Tab(text: "New Human"), // Un toque sutil
                              ],
                            ),
                          ),
                        ),

                        // --- MAGIA 2: El espacio (aire) entre los Tabs y los Formularios ---
                        const SizedBox(height: 16),

                        // Form Views
                        SizedBox(
                          height: 420, // Altura fija o dinámica según prefieras
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildSignInForm(primaryColor),
                              _buildSignUpForm(primaryColor),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  // Footer minimalista
                  Text(
                    "Powered by OpenAI",
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: Colors.white30,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Widget: Sign In Form ---
  Widget _buildSignInForm(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKeySignIn,
        child: Column(
          children: [
            _buildTextField(
              controller: _emailController,
              label: "Email",
              icon: Icons.alternate_email,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: "Password",
              icon: Icons.lock_outline,
              isPassword: true,
              isVisible: _isPasswordVisible,
              onVisibilityToggle: () =>
                  setState(() => _isPasswordVisible = !_isPasswordVisible),
            ),

            // Forgot Password aligned to right
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (_emailController.text.isNotEmpty) {
                    _authManager.sendPasswordResetEmail(
                        context, _emailController.text);
                  } else {
                    _showError('I need an email to do magic.');
                  }
                },
                child: Text(
                  "Forgot Password?",
                  style:
                      GoogleFonts.outfit(color: Colors.white60, fontSize: 12),
                ),
              ),
            ),

            const Spacer(),

            _buildMainButton(
              text: "Enter",
              color: primaryColor,
              onPressed: () async {
                if (!_formKeySignIn.currentState!.validate()) return;

                // 1. Mostrar carga
                _showLoading(context);

                // 2. Intentar iniciar sesión
                bool success = await _authManager.signInWithEmail(
                    context, _emailController.text, _passwordController.text);

                // 3. Ocultar carga (asegurándonos de que el widget siga en pantalla)
                if (mounted) {
                  Navigator.pop(context);
                }

                // 4. Manejar resultado
                if (success) {
                  await _saveUserPreferences(true);
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, 'CamilaPage');
                  }
                } else {
                  // 5. Manejo de error silencioso (AuthManager ya mostró el SnackBar)
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('isLoggedIn', false);
                  if (mounted) {
                    _authManager.softSignOut(context);
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            _buildSocialRow(),
          ],
        ),
      ),
    );
  }

  // --- Widget: Sign Up Form ---
  Widget _buildSignUpForm(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKeySignUp,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildTextField(
                controller: _nameController,
                label: "What should I call you?",
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _createEmailController,
                label: "Email",
                icon: Icons.alternate_email,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _createPasswordController,
                label: "Create Password",
                icon: Icons.lock_outline,
                isPassword: true,
                isVisible: _isCreatePasswordVisible,
                onVisibilityToggle: () => setState(
                    () => _isCreatePasswordVisible = !_isCreatePasswordVisible),
              ),
              const SizedBox(height: 30),
              _buildMainButton(
                text: "Join the Club",
                color: primaryColor,
                onPressed: () async {
                  if (!_formKeySignUp.currentState!.validate()) return;
                  if (_nameController.text.isEmpty) {
                    _showError(
                        'I need a name.'); // Este error sí es local de la UI
                    return;
                  }

                  // 1. Mostrar carga
                  _showLoading(context);

                  // 2. Intentar crear cuenta
                  bool success = await _authManager.createAccountWithEmail(
                    context,
                    _createEmailController.text,
                    _createPasswordController.text,
                    _nameController.text,
                  );

                  // 3. Ocultar carga
                  if (mounted) {
                    Navigator.pop(context);
                  }

                  // 4. Manejar resultado
                  if (success) {
                    await _saveUserPreferences(true);
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, 'CamilaPage');
                    }
                  } else {
                    // 5. Limpieza de estado en caso de fallo
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('isLoggedIn', false);
                    // Opcional: limpiar los campos de texto si quieres que empiecen de cero
                    // _createPasswordController.clear();
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildSocialRow(),
            ],
          ),
        ),
      ),
    );
  }

  // --- Reusable Widgets (Components) ---

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onVisibilityToggle,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !isVisible,
      style: GoogleFonts.outfit(color: Colors.white),
      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white54,
                  size: 20,
                ),
                onPressed: onVisibilityToggle,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildMainButton(
      {required String text,
      required Color color,
      required VoidCallback onPressed}) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [color, const Color(0xFF6C63FF)], // Gradiente de Camila
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          text,
          style: GoogleFonts.outfit(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSocialRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _socialButton(FontAwesomeIcons.google, () async {
          // 1. Mostrar carga
          _showLoading(context);

          // 2. Intentar login con Google
          final result = await _authManager.signInWithGoogle(context);

          // 3. Ocultar carga
          if (mounted) {
            Navigator.pop(context);
          }

          // 4. Manejar resultado (verificando que no sea null por seguridad)
          if (result['signInSuccess'] == true) {
            await _saveUserPreferences(true);
            if (mounted) {
              Navigator.pushReplacementNamed(context, 'CamilaPage');
            }
          } else {
            // 5. Limpieza de estado
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isLoggedIn', false);
          }
        }),
        const SizedBox(width: 20),
        _socialButton(FontAwesomeIcons.apple, () {
          _showError('Apple is being difficult. Coming soon.');
        }),
      ],
    );
  }

  Widget _socialButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Center(
          child: FaIcon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
