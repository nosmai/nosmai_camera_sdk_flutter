// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'nosmai_app_manager.dart';
import 'unified_camera_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-request permissions for instant camera access
  await _preRequestPermissions();

  // Initialize Nosmai SDK once for the entire app
  await NosmaiAppManager.instance.initialize('YOUR_API_KEY_HERE');

  runApp(const MyApp());
}

Future<void> _preRequestPermissions() async {
  try {
    // Pre-request camera permission silently
    await Permission.camera.request();
    // Pre-request microphone permission for video recording
    await Permission.microphone.request();
  } catch (e) {
    // Silently handle permission errors
    print('Permission pre-request failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nosmai Camera',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenHeight < 700;
    final isVerySmallScreen = screenHeight < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: screenWidth * 0.06,
              vertical: isVerySmallScreen
                  ? 12.0
                  : (isSmallScreen ? 16.0 : 24.0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: isVerySmallScreen ? 16 : (isSmallScreen ? 20 : 30),
                ),

                // App Logo/Icon
                Container(
                  width: isVerySmallScreen ? 70 : (isSmallScreen ? 80 : 100),
                  height: isVerySmallScreen ? 70 : (isSmallScreen ? 80 : 100),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6C5CE7),
                        const Color(0xFF6C5CE7).withValues(alpha: 0.6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: isSmallScreen ? 40 : 50,
                    color: Colors.white,
                  ),
                ),

                SizedBox(height: isSmallScreen ? 20 : 30),

                // App Title
                Text(
                  'Nosmai Camera',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 26 : 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'Professional filters & effects',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.white.withValues(alpha: 0.6),
                    letterSpacing: 0.5,
                  ),
                ),

                SizedBox(height: isSmallScreen ? 24 : 40),

                // Main Camera Button
                GestureDetector(
                  onTap: () {
                    // Use optimized navigation for instant transition
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const UnifiedCameraScreen(),
                        transitionDuration: const Duration(
                          milliseconds: 100,
                        ), // Fast transition
                        reverseTransitionDuration: const Duration(
                          milliseconds: 100,
                        ),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    constraints: BoxConstraints(
                      maxWidth: screenWidth * 0.8 > 300
                          ? 300
                          : screenWidth * 0.8,
                    ),
                    height: isSmallScreen ? 48 : 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6C5CE7),
                          const Color(0xFF6C5CE7).withValues(alpha: 0.8),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_enhance_rounded,
                          color: Colors.white,
                          size: isSmallScreen ? 20 : 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Open Camera',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallScreen ? 16 : 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: isSmallScreen ? 24 : 32),

                // Feature Grid
                Container(
                  constraints: BoxConstraints(
                    maxWidth: screenWidth > 400 ? 400 : screenWidth * 0.9,
                  ),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: isSmallScreen ? 8 : 12,
                    mainAxisSpacing: isSmallScreen ? 8 : 12,
                    childAspectRatio: isSmallScreen ? 1.8 : 1.6,
                    children: [
                      _buildFeatureCard(
                        icon: Icons.auto_awesome,
                        title: 'Effects',
                        subtitle: '20+ filters',
                        color: const Color(0xFF6C5CE7),
                        isSmallScreen: isSmallScreen,
                        isVerySmallScreen: isVerySmallScreen,
                      ),
                      _buildFeatureCard(
                        icon: Icons.face_retouching_natural,
                        title: 'Beauty',
                        subtitle: 'AI enhanced',
                        color: const Color(0xFFFF6B6B),
                        isSmallScreen: isSmallScreen,
                        isVerySmallScreen: isVerySmallScreen,
                      ),
                      _buildFeatureCard(
                        icon: Icons.palette_outlined,
                        title: 'Color',
                        subtitle: 'Pro tools',
                        color: const Color(0xFF4ECDC4),
                        isSmallScreen: isSmallScreen,
                        isVerySmallScreen: isVerySmallScreen,
                      ),
                      _buildFeatureCard(
                        icon: Icons.videocam_rounded,
                        title: 'Record',
                        subtitle: 'HD video',
                        color: const Color(0xFFFFD93D),
                        isSmallScreen: isSmallScreen,
                        isVerySmallScreen: isVerySmallScreen,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: isSmallScreen ? 16 : 24),

                // Version info
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),

                SizedBox(height: isSmallScreen ? 16 : 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool isSmallScreen = false,
    bool isVerySmallScreen = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(
          isVerySmallScreen ? 8 : (isSmallScreen ? 10 : 14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: isVerySmallScreen ? 24 : (isSmallScreen ? 28 : 36),
              height: isVerySmallScreen ? 24 : (isSmallScreen ? 28 : 36),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: color,
                size: isVerySmallScreen ? 14 : (isSmallScreen ? 16 : 20),
              ),
            ),
            SizedBox(height: isVerySmallScreen ? 4 : (isSmallScreen ? 6 : 10)),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isVerySmallScreen ? 10 : (isSmallScreen ? 11 : 13),
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: isVerySmallScreen ? 8 : (isSmallScreen ? 9 : 11),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
