import 'dart:async';
import 'dart:io';
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

  /// Allows automated widget tests to bypass the interactive Google prompt.
  static bool bypassAuthForTesting = true;

  static bool get isAuthRequired {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return !bypassAuthForTesting;
    }
    return true;
  }

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  static const FirebaseOptions defaultFirebaseOptions = FirebaseOptions(
    apiKey: 'AIzaSyBpt30WLATz1vAtOIsJLnLCIyz8jNW3V-s',
    appId: '1:885390508088:android:d56224a2dea9c2a758e6cd',
    messagingSenderId: '885390508088',
    projectId: 'kuro-reader',
    storageBucket: 'kuro-reader.firebasestorage.app',
  );

  static StreamSubscription<User?>? _authSubscription;
  static bool _initialized = false;

  /// Initializes Firebase and sets up auth state listeners.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp(options: defaultFirebaseOptions);
        } catch (_) {
          await Firebase.initializeApp();
        }
      }
      isFirebaseAvailable.value = true;
      currentUser.value = FirebaseAuth.instance.currentUser;

      _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        currentUser.value = user;
      });
    } catch (e) {
      isFirebaseAvailable.value = false;
      currentUser.value = null;
      debugPrint('Firebase init: $e');
    }
  }

  /// Initiates Google Sign-In flow.
  static Future<User?> signInWithGoogle() async {
    if (!isFirebaseAvailable.value) {
      await initialize();
      if (!isFirebaseAvailable.value) {
        lastAuthError.value =
            'Serviço de autenticação temporariamente indisponível. Tente novamente.';
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
      lastAuthError.value =
          'Falha ao conectar com o Google. Verifique sua conexão e tente novamente.';
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
