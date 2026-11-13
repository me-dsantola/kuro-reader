import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Web Client ID from Firebase Console / google-services.json (client_type 3).
  /// Required on Android for Google Play Services to generate the OAuth idToken for Firebase Auth.
  static const String serverClientId =
      '885390508088-b5pr402180a4u7l0jtacutvgnd1depuf.apps.googleusercontent.com';

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: serverClientId,
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

      // Reset any previous state to ensure a clean account selector prompt
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

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
    } catch (e, stack) {
      debugPrint('Erro Google Sign-In: $e\n$stack');
      String msg = e.toString();
      if (e is FirebaseAuthException) {
        msg = 'Erro Firebase (${e.code}): ${e.message ?? e.code}';
      } else if (msg.contains('ApiException: 10') ||
          msg.contains(': 10:') ||
          msg.contains('10: ,')) {
        msg =
            'Erro 10 (Google Play): Ative o provedor Google no Firebase Console e confirme a chave SHA-1.';
      } else if (msg.contains('ApiException: 12500') ||
          msg.contains(': 12500:') ||
          msg.contains('12500: ,')) {
        msg =
            'Erro 12500: Configure o e-mail de suporte do projeto no Firebase Console (Autenticação > Configurações).';
      } else if (msg.contains('network_error') ||
          msg.contains('SocketException') ||
          msg.contains('7:')) {
        msg = 'Sem conexão com a internet ou Play Services indisponível.';
      } else if (e is PlatformException && (e.message?.isNotEmpty ?? false)) {
        msg = '${e.message} (${e.code})';
      }
      lastAuthError.value = msg;
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
