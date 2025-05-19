import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:health_app_3/pages/meal_result_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ScanMealPage extends StatefulWidget {
  const ScanMealPage({super.key});

  @override
  State<ScanMealPage> createState() => _ModernScanMealPageState();
}

class _ModernScanMealPageState extends State<ScanMealPage>
    with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  late AnimationController _scanAnimationController;
  final Color customGreen = const Color(0xFF86BF3E);
  final List<Map<String, dynamic>> _scannedMeals = [];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _setupAnimations();
  }

  void _setupAnimations() {
    _scanAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final status = await Permission.camera.request();
    if (status.isGranted) {
      _controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      try {
        await _controller!.initialize();
        setState(() {
          _isCameraInitialized = true;
        });
      } catch (e) {
        print('Error initializing camera: $e');
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _processImage(_selectedImage!);
      });
    }
  }

  void _processImage(File image) async {
    setState(() {
      _isScanning = true;
    });

    try {
      // Send image to your Flask API
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.8.102:5001/predict'), // Use your server IP
      );
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      var response = await request.send();

      String resultText = 'Unknown';
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final data = json.decode(respStr);
        resultText = data['result'] ?? 'Unknown';

        // Add to local list for batch saving later
        _scannedMeals.add({
          'mealName': resultText,
          'imagePath': image.path,
          'timestamp': null, // Will be set on finish
        });
      } else {
        resultText = 'Error: ${response.statusCode}';
      }

      setState(() {
        _isScanning = false;
      });
      _showResultOptionsDialog(resultText, image);
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      _showModernResultDialog('Error: $e');
    }
  }

  Future<void> _saveAllScansToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _scannedMeals.isEmpty) return;
    final now = DateTime.now();
    final batch = FirebaseFirestore.instance.batch();
    final userScanedMealCol = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('scaned-meal');
    for (final meal in _scannedMeals) {
      final docRef = userScanedMealCol.doc();
      batch.set(docRef, {
        'mealName': meal['mealName'],
        'imagePath': meal['imagePath'],
        'timestamp': now,
      });
    }
    await batch.commit();
    setState(() {
      _scannedMeals.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All scanned meals saved!')),
    );
  }

  void _scanMeal() async {
    try {
      if (_controller != null && _controller!.value.isInitialized) {
        setState(() {
          _isScanning = true;
        });

        final image = await _controller!.takePicture();
        final File imageFile = File(image.path);
        _processImage(imageFile);
      }
    } catch (e) {
      print('Error taking picture: $e');
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _showModernResultDialog(String result) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: customGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: customGreen,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Scan Complete',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: customGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Result: $result',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: customGreen,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'Got it',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResultOptionsDialog(String result, File image) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: customGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: customGreen,
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Scan Complete',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: customGreen,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Result: $result',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _saveMealAndShowDetails(result, image);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: customGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'View Details',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: customGreen),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: Text(
                        'Scan Another',
                        style: TextStyle(color: customGreen),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveMealAndShowDetails(String mealName, File image) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You need to be logged in to save meal data')),
      );
      return;
    }

    try {
      // Save the scanned meal to user's collection
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('scaned-meal')
          .add({
        'mealName': mealName,
        'timestamp': FieldValue.serverTimestamp(),
        'imagePath': image.path,
      });

      // Navigate to meal result page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MealResultPage(
            mealImage: image,
          ),
          settings: RouteSettings(
            arguments: {
              'mealImage': image,
              'mealName': mealName,
            },
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving meal data: $e')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _scanAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera or Selected Image
            Positioned.fill(
              child: _selectedImage != null
                  ? Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                    )
                  : _isCameraInitialized
                      ? CameraPreview(_controller!)
                      : Container(
                          color: Colors.black,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
            ),

            // Scanning Animation
            if (_isScanning)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: AnimatedBuilder(
                    animation: _scanAnimationController,
                    builder: (context, child) {
                      return Container(
                        height: 2,
                        margin: EdgeInsets.only(
                          top: MediaQuery.of(context).size.height *
                              _scanAnimationController.value,
                        ),
                        color: customGreen,
                      );
                    },
                  ),
                ),
              ),

            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Scan Your Meal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),

            // Bottom Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isScanning
                          ? 'Analyzing your meal...'
                          : 'Center your meal in the frame',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCircularButton(
                          icon: Icons.photo_library,
                          label: 'Gallery',
                          onTap: _isScanning ? null : _pickImageFromGallery,
                        ),
                        _buildCameraButton(),
                        _buildCircularButton(
                          icon: Icons.flash_on,
                          label: 'Flash',
                          onTap: () {
                            // Add flash functionality
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _scannedMeals.isNotEmpty && !_isScanning
                          ? () async {
                              await _saveAllScansToFirestore();
                              // Navigate to meal results page after saving
                              if (mounted) {
                                Navigator.pushNamed(context, '/meal_result');
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: customGreen,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'Finish & View Results',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraButton() {
    return GestureDetector(
      onTap: _isScanning ? null : _scanMeal,
      child: Container(
        height: 80,
        width: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: customGreen,
          boxShadow: [
            BoxShadow(
              color: customGreen.withOpacity(0.3),
              spreadRadius: 2,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          _isScanning ? Icons.hourglass_bottom : Icons.camera_alt,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}
