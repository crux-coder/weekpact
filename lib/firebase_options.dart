// Configured from the Firebase platform files for the week-pact project.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Firebase web is not configured.');
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => ios,
      TargetPlatform.android => android,
      _ => throw UnsupportedError(
        'Firebase is configured for iOS and Android.',
      ),
    };
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyB_q4rjW59N7uDMO5jC6qKelWX3P3jfPcc",
    appId: "1:674213249994:ios:4af9ae54791562d177c533",
    messagingSenderId: "674213249994",
    projectId: "week-pact",
    storageBucket: "week-pact.firebasestorage.app",
    iosBundleId: "dev.codepeaktrail.weekpact",
  );
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyBooHoUlv26JzW9N_BSYUL-myDs6zqYPPA",
    appId: "1:674213249994:android:ae445aaf90c36fed77c533",
    messagingSenderId: "674213249994",
    projectId: "week-pact",
    storageBucket: "week-pact.firebasestorage.app",
  );
}
