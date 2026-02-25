// ─────────────────────────────────────────────────────────────────────────────
// Firebase configuration for project: polyai-426af
//
// Generated manually from `firebase apps:sdkconfig` output for the two
// registered Drezzy apps:
//   Android — com.drezzy.app  (App ID: 1:98961097954:android:91627ea37ac4146aa6cabb)
//   iOS     — com.drezzy.app  (App ID: 1:98961097954:ios:0aa82cbd47a9ccb0a6cabb)
//
// When native platform folders are created (flutter create / flutter create
// --org com.drezzy .), place the matching native config files:
//   Android : android/app/google-services.json
//   iOS     : ios/Runner/GoogleService-Info.plist
// Both can be downloaded from:
//   https://console.firebase.google.com/project/polyai-426af/settings/general
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      // Web is not yet configured for Drezzy.
      // Register a Web app at:
      //   https://console.firebase.google.com/project/polyai-426af/settings/general
      throw UnsupportedError(
        'DefaultFirebaseOptions: Web platform is not yet configured.\n'
        'Register a Web app in the Firebase console and add its config here.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions: macOS is not yet configured.\n'
          'Run: flutterfire configure --project=polyai-426af',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions: Windows is not yet configured.\n'
          'Run: flutterfire configure --project=polyai-426af',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions: Linux is not yet configured.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions: unsupported platform '
          '"${defaultTargetPlatform.name}".',
        );
    }
  }

  // ── Android ──────────────────────────────────────────────────────────────
  // Source: firebase apps:sdkconfig ANDROID 1:98961097954:android:91627ea37ac4146aa6cabb
  // Package name : com.drezzy.app

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBjjMarQH3pyFKGPlCiYBjLUgYpIkXmiCM',
    appId: '1:98961097954:android:91627ea37ac4146aa6cabb',
    messagingSenderId: '98961097954',
    projectId: 'polyai-426af',
    authDomain: 'polyai-426af.firebaseapp.com',
    storageBucket: 'polyai-426af.firebasestorage.app',
  );

  // ── iOS ──────────────────────────────────────────────────────────────────
  // Source: firebase apps:sdkconfig IOS 1:98961097954:ios:0aa82cbd47a9ccb0a6cabb
  // Bundle ID : com.drezzy.app

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDuDJQUWDXItLLsCJPNXQMMngbtdpIeSuk',
    appId: '1:98961097954:ios:0aa82cbd47a9ccb0a6cabb',
    messagingSenderId: '98961097954',
    projectId: 'polyai-426af',
    authDomain: 'polyai-426af.firebaseapp.com',
    storageBucket: 'polyai-426af.firebasestorage.app',
    iosBundleId: 'com.drezzy.app',
    // iosClientId is only required for native Google Sign-In.
    // Add it here once a Google OAuth client is configured in the console.
  );
}
