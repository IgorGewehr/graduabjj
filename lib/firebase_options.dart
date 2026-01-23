import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default Firebase configuration for GraduaBJJ
///
/// IMPORTANT: For production, you need to:
/// 1. Add your Android app to Firebase Console and download google-services.json
/// 2. Add your iOS app to Firebase Console and download GoogleService-Info.plist
///
/// You can also use `flutterfire configure` to generate these automatically.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCOvI6fk-3Js0cp0PNpVFRUKzR5Cz9OK58',
    appId: '1:880937749202:web:6973d414100457ceeb3b0b',
    messagingSenderId: '880937749202',
    projectId: 'arpjj-76350',
    authDomain: 'arpjj-76350.firebaseapp.com',
    storageBucket: 'arpjj-76350.firebasestorage.app',
  );

  // Android configuration
  // TODO: Replace with your actual Android app configuration
  // Run `flutterfire configure` or add app in Firebase Console
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCOvI6fk-3Js0cp0PNpVFRUKzR5Cz9OK58',
    appId: '1:880937749202:android:YOUR_ANDROID_APP_ID',
    messagingSenderId: '880937749202',
    projectId: 'arpjj-76350',
    storageBucket: 'arpjj-76350.firebasestorage.app',
  );

  // iOS configuration
  // TODO: Replace with your actual iOS app configuration
  // Run `flutterfire configure` or add app in Firebase Console
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:880937749202:ios:YOUR_IOS_APP_ID',
    messagingSenderId: '880937749202',
    projectId: 'arpjj-76350',
    storageBucket: 'arpjj-76350.firebasestorage.app',
    iosBundleId: 'com.graduabjj.app',
  );

  // macOS configuration
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: '1:880937749202:macos:YOUR_MACOS_APP_ID',
    messagingSenderId: '880937749202',
    projectId: 'arpjj-76350',
    storageBucket: 'arpjj-76350.firebasestorage.app',
    iosBundleId: 'com.graduabjj.app',
  );

  // Windows configuration
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCOvI6fk-3Js0cp0PNpVFRUKzR5Cz9OK58',
    appId: '1:880937749202:web:6973d414100457ceeb3b0b',
    messagingSenderId: '880937749202',
    projectId: 'arpjj-76350',
    authDomain: 'arpjj-76350.firebaseapp.com',
    storageBucket: 'arpjj-76350.firebasestorage.app',
  );
}
