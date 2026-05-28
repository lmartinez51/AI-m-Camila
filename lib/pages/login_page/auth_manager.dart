import 'dart:io';
import 'package:aimcamila/models/user_model.dart';
import 'package:aimcamila/providers/user_provider.dart';
import 'package:aimcamila/providers/video_provider.dart';
import 'package:aimcamila/database/objectbox_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthManager {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // Función de inicio de sesión
// Función de inicio de sesión
  Future<bool> signInWithEmail(
      BuildContext context, String email, String password) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists || userDoc.data() == null) {
        throw Exception('User data not found in database.');
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      userProvider.setUser(
        UserModel(
          uid: userCredential.user!.uid,
          email: email,
          name: userData['name'] ?? 'Unknown',
          gender: userData['gender'],
          personalBackground: userData['personalBackground'],
          nickname: userData['nickname'],
          interests: userData['interests'],
          phoneNumber: userData['phoneNumber'],
          relationship: userData['relationship'],
        ),
      );

      // 🔒 ABRIR LA BÓVEDA DE OBJECTBOX
      objectbox = await ObjectBoxService.create(userCredential.user!.uid);
      isObjectBoxReady = true; // 🛡️ Levantamos el escudo
      debugPrint("🔓 Bóveda abierta para: ${userCredential.user!.uid}");
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Auth Error: ${e.code} - ${e.message}');
      String errorMessage = (e.code == 'invalid-credential')
          ? 'The email address or password is incorrect. Try again.'
          : 'Authentication failed. Please check your credentials.';
      _showErrorSnackBar(context, errorMessage);
      return false;
    } catch (e) {
      debugPrint('General Error signing in: $e');
      _showErrorSnackBar(
          context, 'An unexpected error occurred. Try again later.');
      return false;
    }
  }

  Future<Map<String, dynamic>> signInWithGoogle(BuildContext context) async {
    try {
      debugPrint('🔄 Starting Google Sign-In (mobile)');
      await _googleSignIn.signOut();
      await _googleSignIn.initialize();
      final googleUser = await _googleSignIn.authenticate();

      debugPrint('📍 Google Account selected: ${googleUser.displayName}');
      final googleAuth = googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        debugPrint('⚠️ idToken is null — cannot authenticate with Firebase');
        return {'signInSuccess': false};
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user!;

      debugPrint('✅ Firebase authenticated: ${user.displayName}');

      final DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final bool isNewUser = !userDoc.exists;
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      if (isNewUser) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'name': user.displayName,
          'email': user.email,
        });

        userProvider.setUser(UserModel(
          uid: user.uid,
          email: user.email!,
          name: user.displayName!,
        ));
      } else {
        final userData = userDoc.data() as Map<String, dynamic>;
        userProvider.setUser(UserModel(
          uid: user.uid,
          email: user.email!,
          name: userData['name'] ?? user.displayName!,
          gender: userData['gender'] is List ? (userData['gender'] as List).join(', ') : userData['gender'],
          personalBackground: userData['personalBackground'] is List ? (userData['personalBackground'] as List).join(', ') : userData['personalBackground'],
          nickname: userData['nickname'] is List ? (userData['nickname'] as List).join(', ') : userData['nickname'],
          interests: userData['interests'] is List ? (userData['interests'] as List).join(', ') : userData['interests'],
          phoneNumber: userData['phoneNumber'] is List ? (userData['phoneNumber'] as List).join(', ') : userData['phoneNumber'],
          relationship: userData['relationship'] is List ? (userData['relationship'] as List).join(', ') : userData['relationship'],
        ));
      }

      // 🔒 ABRIR LA BÓVEDA DE OBJECTBOX
      objectbox = await ObjectBoxService.create(user.uid);
      isObjectBoxReady = true; // 🛡️ Levantamos el escudo
      debugPrint("🔓 Bóveda abierta para: ${user.uid}");

      return {
        'signInSuccess': true,
        'isNewUser': isNewUser,
      };
    } catch (e, stacktrace) {
      debugPrint('❌ Google sign-in failed: $e');
      debugPrint('Stacktrace: $stacktrace');
      _showErrorSnackBar(context, 'Google Sign-In failed. Please try again.');
      return {'signInSuccess': false};
    }
  }

  Future<void> signOut(BuildContext context) async {
    try {
      debugPrint('🔄 Signing out user...');

      // 🔒 CERRAR LA BÓVEDA DE OBJECTBOX
      if (isObjectBoxReady) {
        objectbox.closeStore();
        isObjectBoxReady = false;
        debugPrint("🔒 Bóveda de ObjectBox cerrada.");
      }

      // 🔴 Cerrar sesión Firebase
      await _auth.signOut();

      // 🔴 Cerrar sesión Google (MUY IMPORTANTE)
      await _googleSignIn.signOut();

      // Limpiar almacenamiento local
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Limpiar providers
      Provider.of<UserProvider>(context, listen: false).clearUser();
      Provider.of<VideoProvider>(context, listen: false).clearProvider();

      debugPrint('✓ User signed out successfully');

      // 🚀 NUEVA REDIRECCIÓN: En vez de cerrar la app como Android 4.0,
      // limpiamos el historial de navegación y te mandamos al Login.
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      debugPrint('❌ Error during sign out: $e');
    }
  }

  Future<void> softSignOut(BuildContext context) async {
    try {
      // 🔒 CERRAR LA BÓVEDA DE OBJECTBOX
      if (isObjectBoxReady) {
        objectbox.closeStore();
        isObjectBoxReady = false;
        debugPrint("🔒 Bóveda de ObjectBox cerrada.");
      }
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Provider.of<UserProvider>(context, listen: false).clearUser();
      Provider.of<VideoProvider>(context, listen: false).clearProvider();
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  Future<bool> createAccountWithEmail(
      BuildContext context, String email, String password, String name) async {
    // Eliminar espacios al final del nombre
    name = name.replaceAll(RegExp(r'\s+$'), '');

    try {
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      String uid = userCredential.user!.uid;

      // Almacenar el nombre, email
      await _firestore.collection('users').doc(uid).set({
        //'uid': uid, // Incluir el UID en el documento
        'name': name,
        'email': email,
      });

      await userCredential.user!.updateProfile(displayName: name);

      // Almacenar el usuario en el provider
      Provider.of<UserProvider>(context, listen: false).setUser(
        UserModel(uid: uid, email: email, name: name),
      );

      // 🔒 ABRIR LA BÓVEDA DE OBJECTBOX
      objectbox = await ObjectBoxService.create(uid);
      debugPrint("🔓 Bóveda abierta para: $uid");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account created successfully',
            style: TextStyle(
              fontFamily: 'Readex Pro',
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF4B39EF),
        ),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Error code: ${e.code}');
      debugPrint('Error code: ${e.message}');
      String errorMessage;
      if (e.code == 'weak-password') {
        errorMessage = 'The provided password is too weak.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'An account already exists with that email.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'The email address is invalid.';
      } else {
        errorMessage =
            'An error occurred while creating the account, possibly due to network issue.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage,
            style: const TextStyle(
              fontFamily: 'Readex Pro',
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: const Color(0xFF4B39EF),
        ),
      );
      await Future.delayed(const Duration(seconds: 3));
      _showErrorSnackBar(context, errorMessage);
      return false;
    } catch (e) {
      // NUEVO: Atrapa errores generales (ej. si Firestore falla al guardar)
      debugPrint('General Error creating account: $e');
      _showErrorSnackBar(context,
          'An unexpected error occurred while setting up your account.');
      return false;
    }
  }

  Future<String?> uploadImage(File imageFile) async {
    try {
      final storage = FirebaseStorage.instance;
      final ref = storage
          .ref()
          .child('images/${DateTime.now().millisecondsSinceEpoch}.jpg');
      final uploadTask = ref.putFile(imageFile);

      await uploadTask.whenComplete(() {
        debugPrint('Imagen subida correctamente!');
      });

      final downloadURL = await ref.getDownloadURL();
      debugPrint('URL de descarga: $downloadURL');
      return downloadURL;
    } catch (e) {
      debugPrint('Error al subir la imagen: $e');
      return null;
    }
  }

  Future<void> updateUserProfile(BuildContext context, UserModel user) async {
    try {
      // Crear un mapa con los campos obligatorios
      Map<String, dynamic> userData = {
        'gender': user.gender,
        'personalBackground': user.personalBackground,
        'nickname': user.nickname,
        'interests': user.interests,
        'phoneNumber': user.phoneNumber,
        'relationship': user.relationship,
      };

      // Actualizar el perfil del usuario en Firestore
      await _firestore.collection('users').doc(user.uid).update(userData);

      // Actualizar el usuario en el provider
      Provider.of<UserProvider>(context, listen: false).setUser(user);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile updated successfully',
            style: TextStyle(
              fontFamily: 'Readex Pro',
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF4B39EF),
        ),
      );
    } catch (e) {
      debugPrint('Error updating profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'An error occurred while updating the profile.',
            style: TextStyle(
              fontFamily: 'Readex Pro',
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF4B39EF),
        ),
      );
    }
  }

  Future<void> sendPasswordResetEmail(
      BuildContext context, String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      // Mostrar un mensaje de éxito
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset email sent.',
            style: TextStyle(
              fontFamily: 'Readex Pro',
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF4B39EF),
        ),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Error code: ${e.code}');
      String errorMessage = 'An error occurred while sending reset email.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage,
            style: const TextStyle(
              fontFamily: 'Readex Pro',
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF4B39EF),
        ),
      );
    }
  }

  Future<void> deleteAccount(BuildContext context) async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        debugPrint('User name: ${user.displayName}');
      } else {
        debugPrint('No user is currently signed in.');
      }

      if (user != null) {
        // Eliminar el documento del usuario en Firestore
        await _firestore.collection('users').doc(user.uid).delete();

        // Update 'isLoggedIn' and delete Firebase Authentication account
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', false);
        await user.delete();
        await prefs.remove('hasShownWelcomeMessage');

        // Limpiar el estado del usuario en la aplicación
        Provider.of<UserProvider>(context, listen: false).clearUser();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account deleted successfully',
              style: TextStyle(
                fontFamily: 'Readex Pro',
                color: Colors.white,
                fontSize: 12,
                letterSpacing: 0,
              ),
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF4B39EF),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Error code: ${e.code}');
      String errorMessage = 'An error occurred while deleting the account.';

      // NUEVO: Manejo del error de seguridad de Firebase
      if (e.code == 'requires-recent-login') {
        errorMessage =
            'For security reasons, please log out and log back in before deleting your account.';
      }

      _showErrorSnackBar(context, errorMessage);
    } catch (e) {
      debugPrint('Error deleting account: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'An error occurred while deleting the account.',
            style: TextStyle(
              fontFamily: 'Readex Pro',
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF4B39EF),
        ),
      );
    }
  }

  // Helper para no repetir el código del SnackBar
  void _showErrorSnackBar(BuildContext context, String message) {
    if (!context.mounted) return; // Evita errores si la pantalla ya se cerró
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily:
                'Readex Pro', // O 'Outfit' si usaste mi diseño anterior ;)
            color: Colors.white,
            fontSize: 12,
            letterSpacing: 0,
          ),
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF4B39EF),
      ),
    );
  }
}
