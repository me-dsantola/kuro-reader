import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Manages Google Authentication and Firebase Auth lifecycle.
/// Designed defensively: if Firebase configuration (such as google-services.json)
/// is not yet present, the app gracefully degrades without crashing.
class CloudAuthService {
  static final ValueNotifier<User?> currentUser = ValueNotifier<User?>(null);
  static final ValueNotifier<bool> isFirebaseAvailable = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isSigningIn = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> lastAuthError = ValueNotifier<String?>(null);

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  static StreamSubscription<User?>? _authSubscription;
  static bool _initialized = false;

  /// Initializes Firebase and sets up auth state listeners.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      isFirebaseAvailable.value = true;
      currentUser.value = FirebaseAuth.instance.currentUser;

      _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        currentUser.value = user;
      });
    } catch (e) {
      // Firebase not configured yet (e.g. google-services.json pending)
      isFirebaseAvailable.value = false;
      currentUser.value = null;
      debugPrint('Firebase não inicializado: $e');
    }
  }

  /// Initiates Google Sign-In flow.
  static Future<User?> signInWithGoogle() async {
    if (!isFirebaseAvailable.value) {
      await initialize();
      if (!isFirebaseAvailable.value) {
        lastAuthError.value = 'Firebase não está configurado. Adicione o google-services.json.';
        return null;
      }
    }

    try {
      isSigningIn.value = true;
      lastAuthError.value = null;

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in prompt
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      currentUser.value = userCredential.user;
      return userCredential.user;
    } catch (e) {
      lastAuthError.value = 'Falha ao autenticar com Google: $e';
      debugPrint('Erro Google Sign-In: $e');
      return null;
    } finally {
      isSigningIn.value = false;
    }
  }

  /// Signs the user out of Firebase and Google Sign-In.
  static Future<void> signOut() async {
    try {
      if (isFirebaseAvailable.value) {
        await FirebaseAuth.instance.signOut();
      }
      await _googleSignIn.signOut();
    } catch (_) {}
    currentUser.value = null;
  }
}
