import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Full-screen pinch-zoom image viewer.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({
    super.key,
    required this.bytes,
    this.title = 'Photo',
  });

  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const Text(
              'Could not display image',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
