import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase configuration options for GraduaBJJ
///
/// These options are configured for the arpjj-76350 Firebase project.
/// To update, generate new config files from Firebase Console.
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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
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

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCOvI6fk-3Js0cp0PNpVFRUKzR5Cz9OK58',
    appId: '1:880937749202:android:REPLACE_WITH_ANDROID_APP_ID',
    messagingSenderId: '880937749202',
    projectId: 'arpjj-76350',
    storageBucket: 'arpjj-76350.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCOvI6fk-3Js0cp0PNpVFRUKzR5Cz9OK58',
    appId: '1:880937749202:ios:REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: '880937749202',
    projectId: 'arpjj-76350',
    storageBucket: 'arpjj-76350.firebasestorage.app',
    iosBundleId: 'com.graduabjj.graduabjj',
  );
}
