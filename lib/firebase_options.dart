// Firebase configuration for DiaCare.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DiaCare is not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDFU0KsEn7_5BQ6hosHesaZBKBoGQiPwEo',
    appId: '1:2509170380:android:e1429744c082d80614c469',
    messagingSenderId: '2509170380',
    projectId: 'diacare-fe2d1',
    storageBucket: 'diacare-fe2d1.firebasestorage.app',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCrTy4ZepaRiVj4nYwlTqUQWXhqCy4g9JQ',
    appId: '1:2509170380:web:f8accd3656bcca1f14c469',
    messagingSenderId: '2509170380',
    projectId: 'diacare-fe2d1',
    authDomain: 'diacare-fe2d1.firebaseapp.com',
    storageBucket: 'diacare-fe2d1.firebasestorage.app',
    measurementId: 'G-VZ1L39Q6KW',
  );
}
