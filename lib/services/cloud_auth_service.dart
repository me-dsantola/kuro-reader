import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_android/google_sign_in_android.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

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

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (GoogleSignInPlatform.instance is! GoogleSignInAndroid) {
          GoogleSignInAndroid.registerWith();
        }
      } catch (e) {
        debugPrint('GoogleSignInAndroid registerWith: $e');
      }
    }

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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        if (GoogleSignInPlatform.instance is! GoogleSignInAndroid) {
          GoogleSignInAndroid.registerWith();
        }
      } catch (_) {}
    }

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

  static String _mapFirebaseAuthErrorPt(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'E-mail inválido. Verifique o endereço digitado.';
      case 'user-disabled':
        return 'Esta conta foi desativada.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou senha incorretos.';
      case 'email-already-in-use':
        return 'Já existe uma conta cadastrada com este e-mail.';
      case 'weak-password':
        return 'A senha deve ter pelo menos 6 caracteres.';
      case 'network-request-failed':
        return 'Sem conexão com a internet. Tente novamente.';
      case 'too-many-requests':
        return 'Muitas tentativas seguidas. Aguarde alguns instantes.';
      default:
        return (e.message?.isNotEmpty ?? false)
            ? 'Erro Firebase (${e.code}): ${e.message}'
            : 'Não foi possível concluir a autenticação (${e.code}).';
    }
  }

  static Future<bool> _ensureFirebaseReadyForAuth() async {
    if (isFirebaseAvailable.value) return true;
    await initialize();
    if (!isFirebaseAvailable.value) {
      lastAuthError.value =
          'Serviço de autenticação temporariamente indisponível. Tente novamente.';
      return false;
    }
    return true;
  }

  /// Signs in with an existing email and password (shared with the YOMI Web portal).
  static Future<User?> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    if (!await _ensureFirebaseReadyForAuth()) return null;

    try {
      isSigningIn.value = true;
      lastAuthError.value = null;

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      currentUser.value = credential.user;
      return credential.user;
    } on FirebaseAuthException catch (e) {
      lastAuthError.value = _mapFirebaseAuthErrorPt(e);
      return null;
    } catch (e, stack) {
      debugPrint('Erro Email Sign-In: $e\n$stack');
      lastAuthError.value = 'Não foi possível entrar com e-mail e senha.';
      return null;
    } finally {
      isSigningIn.value = false;
    }
  }

  /// Registers a new account with name, email and password.
  static Future<User?> registerWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    if (!await _ensureFirebaseReadyForAuth()) return null;

    try {
      isSigningIn.value = true;
      lastAuthError.value = null;

      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final cleanName = name.trim();
      User? user = credential.user;
      if (user != null && cleanName.isNotEmpty) {
        try {
          await user.updateDisplayName(cleanName);
          await user.reload();
          user = FirebaseAuth.instance.currentUser ?? user;
        } catch (e) {
          debugPrint('Aviso ao definir displayName: $e');
        }
      }
      currentUser.value = user;
      return user;
    } on FirebaseAuthException catch (e) {
      lastAuthError.value = _mapFirebaseAuthErrorPt(e);
      return null;
    } catch (e, stack) {
      debugPrint('Erro Email Sign-Up: $e\n$stack');
      lastAuthError.value = 'Não foi possível criar sua conta agora.';
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
