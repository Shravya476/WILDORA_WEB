import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyABrSVkvce2iVC4zSC4MfI-fgPzF12DgLA",
      authDomain: "hwc-alert-499711.firebaseapp.com",
      projectId: "hwc-alert-499711",
      storageBucket: "hwc-alert-499711.firebasestorage.app",
      messagingSenderId: "855616726627",
      appId: "1:855616726627:web:ba0901e2941463857efa56",
      measurementId: "G-GZPN81G9KK",
    ),
  );
  runApp(const HWCApp());
}

class HWCApp extends StatelessWidget {
  const HWCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HWC Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          }
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF2E7D32),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forest, size: 80, color: Colors.white),
            SizedBox(height: 20),
            Text('HWC Alert',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
