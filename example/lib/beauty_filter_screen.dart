import 'package:flutter/material.dart';
import 'package:nosmai_camera_sdk/nosmai_flutter.dart';
import 'nosmai_app_manager.dart';

class BeautyFilterScreen extends StatefulWidget {
  const BeautyFilterScreen({super.key});

  @override
  State<BeautyFilterScreen> createState() => _BeautyFilterScreenState();
}

class _BeautyFilterScreenState extends State<BeautyFilterScreen> {
  final NosmaiFlutter _nosmai = NosmaiAppManager.instance.nosmai;

  // Beauty filter values
  double _skinSmoothing = 0.0;
  double _skinWhitening = 0.0;
  double _faceSlimming = 0.0;
  double _eyeEnlargement = 0.0;
  double _noseSize = 50.0;
  double _brightness = 0.0;
  double _contrast = 1.0;
  double _sharpening = 0.0;

  // RGB values
  double _redValue = 1.0;
  double _greenValue = 1.0;
  double _blueValue = 1.0;

  // Other filters
  double _hueAngle = 0.0;
  double _temperature = 5000.0; // Normal color temperature
  double _tint = 0.0;

  // HSB values
  double _hsbHue = 0.0;
  double _hsbSaturation = 1.0;
  double _hsbBrightness = 1.0; // 1.0 is normal, not 0.0!

  bool _isInitialized = false;
  String _selectedCategory = 'beauty';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // Configure camera if not already done
      await _nosmai.configureCamera(
        position: NosmaiCameraPosition.front,
      );

      // Face detection is automatically enabled when beauty filters are used

      // Start processing
      await _nosmai.startProcessing();

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _applyBeautyFilters() async {
    try {
      await _nosmai.applySkinSmoothing(_skinSmoothing);
      await _nosmai.applySkinWhitening(_skinWhitening);
      await _nosmai.applyFaceSlimming(_faceSlimming);
      await _nosmai.applyEyeEnlargement(_eyeEnlargement);
      await _nosmai.applyNoseSize(_noseSize);
    } catch (e) {
      debugPrint('Error applying beauty filters: $e');
    }
  }

  void _applyColorFilters() async {
    try {
      await _nosmai.applyBrightnessFilter(_brightness);
      await _nosmai.applyContrastFilter(_contrast);
      await _nosmai.applyRGBFilter(
        red: _redValue,
        green: _greenValue,
        blue: _blueValue,
      );
    } catch (e) {
      debugPrint('Error applying color filters: $e');
    }
  }

  void _applyEffectFilters() async {
    try {
      await _nosmai.applySharpening(_sharpening);
      await _nosmai.applyHue(_hueAngle);
      await _nosmai.applyWhiteBalance(
        temperature: _temperature,
        tint: _tint,
      );
    } catch (e) {
      debugPrint('Error applying effect filters: $e');
    }
  }

  void _applyHSBFilters() async {
    try {
      // Reset HSB first since adjustments are additive
      await _nosmai.resetHSBFilter();

      // Apply HSB values (Note: Hue in HSB is not implemented in SDK)
      // So we use the standalone applyHue filter for hue adjustment
      if (_hsbHue != 0.0) {
        // Convert from -360 to 360 range to 0 to 360 range for applyHue
        double hueValue = _hsbHue < 0 ? _hsbHue + 360 : _hsbHue;
        await _nosmai.applyHue(hueValue);
      }

      // Apply saturation and brightness through HSB
      await _nosmai.adjustHSB(
        hue: 0.0, // Always 0 since hue is not implemented in HSB
        saturation: _hsbSaturation,
        brightness: _hsbBrightness,
      );
    } catch (e) {
      debugPrint('Error applying HSB filters: $e');
    }
  }

  void _resetAllFilters() async {
    setState(() {
      // Beauty filters
      _skinSmoothing = 0.0;
      _skinWhitening = 0.0;
      _faceSlimming = 0.0;
      _eyeEnlargement = 0.0;

      // Color filters
      _brightness = 0.0;
      _contrast = 1.0;
      _redValue = 1.0;
      _greenValue = 1.0;
      _blueValue = 1.0;

      // Effect filters
      _sharpening = 0.0;
      _hueAngle = 0.0;
      _temperature = 5000.0;
      _tint = 0.0;

      // HSB filters
      _hsbHue = 0.0;
      _hsbSaturation = 1.0;
      _hsbBrightness = 1.0;
    });

    try {
      await _nosmai.removeBuiltInFilters();
      await _nosmai.resetHSBFilter();
    } catch (e) {
      debugPrint('Error resetting filters: $e');
    }
  }

  Widget _buildCategoryChip(String category, String label, IconData icon) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6C5CE7)
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6C5CE7)
                : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required VoidCallback onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value.toStringAsFixed(max > 2 ? 0 : 2),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF6C5CE7),
              inactiveTrackColor: Colors.white30,
              thumbColor: const Color(0xFF6C5CE7),
              overlayColor: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: (_) => onChangeEnd(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeautyControls() {
    return Column(
      children: [
        _buildSlider(
          label: 'Skin Smoothing',
          value: _skinSmoothing,
          min: 0.0,
          max: 10.0,
          onChanged: (value) => setState(() => _skinSmoothing = value),
          onChangeEnd: _applyBeautyFilters,
        ),
        _buildSlider(
          label: 'Skin Whitening',
          value: _skinWhitening,
          min: 0.0,
          max: 10.0,
          onChanged: (value) => setState(() => _skinWhitening = value),
          onChangeEnd: _applyBeautyFilters,
        ),
        _buildSlider(
          label: 'Face Slimming',
          value: _faceSlimming,
          min: 0.0,
          max: 10.0,
          onChanged: (value) => setState(() => _faceSlimming = value),
          onChangeEnd: _applyBeautyFilters,
        ),
        _buildSlider(
          label: 'Eye Enlargement',
          value: _eyeEnlargement,
          min: 0.0,
          max: 10.0,
          onChanged: (value) => setState(() => _eyeEnlargement = value),
          onChangeEnd: _applyBeautyFilters,
        ),
        _buildSlider(
          label: 'Nose Size',
          value: _noseSize,
          min: 0.0,
          max: 100.0,
          onChanged: (value) => setState(() => _noseSize = value),
          onChangeEnd: _applyBeautyFilters,
        ),
      ],
    );
  }

  Widget _buildColorControls() {
    return Column(
      children: [
        _buildSlider(
          label: 'Brightness',
          value: _brightness,
          min: -1.0,
          max: 1.0,
          onChanged: (value) => setState(() => _brightness = value),
          onChangeEnd: _applyColorFilters,
        ),
        _buildSlider(
          label: 'Contrast',
          value: _contrast,
          min: 0.0,
          max: 2.0,
          onChanged: (value) => setState(() => _contrast = value),
          onChangeEnd: _applyColorFilters,
        ),
        _buildSlider(
          label: 'Red',
          value: _redValue,
          min: 0.0,
          max: 2.0,
          onChanged: (value) => setState(() => _redValue = value),
          onChangeEnd: _applyColorFilters,
        ),
        _buildSlider(
          label: 'Green',
          value: _greenValue,
          min: 0.0,
          max: 2.0,
          onChanged: (value) => setState(() => _greenValue = value),
          onChangeEnd: _applyColorFilters,
        ),
        _buildSlider(
          label: 'Blue',
          value: _blueValue,
          min: 0.0,
          max: 2.0,
          onChanged: (value) => setState(() => _blueValue = value),
          onChangeEnd: _applyColorFilters,
        ),
      ],
    );
  }

  Widget _buildEffectControls() {
    return Column(
      children: [
        _buildSlider(
          label: 'Sharpening',
          value: _sharpening,
          min: 0.0,
          max: 10.0,
          onChanged: (value) => setState(() => _sharpening = value),
          onChangeEnd: _applyEffectFilters,
        ),
        _buildSlider(
          label: 'Hue',
          value: _hueAngle,
          min: 0.0,
          max: 360.0,
          onChanged: (value) => setState(() => _hueAngle = value),
          onChangeEnd: _applyEffectFilters,
        ),
        _buildSlider(
          label: 'Temperature',
          value: _temperature,
          min: 2000.0,
          max: 8000.0,
          onChanged: (value) => setState(() => _temperature = value),
          onChangeEnd: _applyEffectFilters,
        ),
        _buildSlider(
          label: 'Tint',
          value: _tint,
          min: -1.0,
          max: 1.0,
          onChanged: (value) => setState(() => _tint = value),
          onChangeEnd: _applyEffectFilters,
        ),
      ],
    );
  }

  Widget _buildHSBControls() {
    return Column(
      children: [
        _buildSlider(
          label: 'Hue',
          value: _hsbHue,
          min: -360.0,
          max: 360.0,
          onChanged: (value) => setState(() => _hsbHue = value),
          onChangeEnd: _applyHSBFilters,
        ),
        _buildSlider(
          label: 'Saturation',
          value: _hsbSaturation,
          min: 0.0,
          max: 2.0,
          onChanged: (value) => setState(() => _hsbSaturation = value),
          onChangeEnd: _applyHSBFilters,
        ),
        _buildSlider(
          label: 'Brightness',
          value: _hsbBrightness,
          min: 0.0,
          max: 2.0,
          onChanged: (value) => setState(() => _hsbBrightness = value),
          onChangeEnd: _applyHSBFilters,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Beauty & Filters',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _resetAllFilters,
            tooltip: 'Reset All',
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: () async {
              await _nosmai.switchCamera();
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Camera preview
          if (_isInitialized)
            const Positioned.fill(
              child: RepaintBoundary(
                child: NosmaiCameraPreview(
                  key: ValueKey('beauty_camera_preview'),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            ),

          // Controls overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Category selector
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          _buildCategoryChip('beauty', 'Beauty', Icons.face),
                          const SizedBox(width: 8),
                          _buildCategoryChip('color', 'Color', Icons.palette),
                          const SizedBox(width: 8),
                          _buildCategoryChip(
                              'effect', 'Effects', Icons.auto_awesome),
                          const SizedBox(width: 8),
                          _buildCategoryChip('hsb', 'HSB', Icons.tune),
                        ],
                      ),
                    ),

                    // Controls based on selected category
                    Container(
                      height: 250,
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        child: Builder(
                          builder: (context) {
                            switch (_selectedCategory) {
                              case 'beauty':
                                return _buildBeautyControls();
                              case 'color':
                                return _buildColorControls();
                              case 'effect':
                                return _buildEffectControls();
                              case 'hsb':
                                return _buildHSBControls();
                              default:
                                return const SizedBox.shrink();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Don't cleanup SDK - let app manager handle it
    super.dispose();
  }
}
