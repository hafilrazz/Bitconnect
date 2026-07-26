import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../identity_store.dart';
import '../mesh_controller.dart';
import '../theme/app_theme.dart';

/// Show Bitconnect ID as QR + open scanner.
class QrShareScreen extends StatelessWidget {
  const QrShareScreen({super.key, required this.controller});

  final MeshController controller;

  @override
  Widget build(BuildContext context) {
    final id = controller.netlessId;
    return Scaffold(
      appBar: AppBar(title: const Text('My Bitconnect ID')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Friends scan this to add you for Worldwide E2E',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: 'bitconnect://id/$id',
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF0B6E4F),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF0B6E4F),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              id,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID copied')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy ID'),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QrScanScreen(controller: controller),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan contact QR'),
            ),
          ],
        ),
      ),
    );
  }
}

/// QR scanner using **still photos** (reliable on Android).
///
/// Image-stream → ML Kit is flaky across OEMs. We preview with [CameraPreview]
/// and every ~700ms take a still photo and decode QR from the file path.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.controller});

  final MeshController controller;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with WidgetsBindingObserver {
  final _manual = TextEditingController();
  final _scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  CameraController? _camera;
  Timer? _poll;
  bool _handled = false;
  bool _busy = false;
  bool _starting = true;
  bool _permissionDenied = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _manual.dispose();
    unawaited(_closeCamera());
    _scanner.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _poll?.cancel();
      _poll = null;
    } else if (state == AppLifecycleState.resumed &&
        _camera != null &&
        _camera!.value.isInitialized &&
        !_handled) {
      _startPolling();
    }
  }

  Future<void> _openCamera() async {
    setState(() {
      _starting = true;
      _error = null;
      _permissionDenied = false;
      _status = 'Requesting camera…';
    });

    final camPerm = await Permission.camera.request();
    if (!camPerm.isGranted) {
      if (mounted) {
        setState(() {
          _starting = false;
          _permissionDenied = true;
          _error = 'Camera permission denied. Paste ID or pick a QR photo.';
        });
      }
      return;
    }

    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('No camera');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await c.initialize();
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await c.setFlashMode(FlashMode.off);
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      _camera = c;
      setState(() {
        _starting = false;
        _status = 'Hold QR inside the box…';
      });
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Camera open failed. Use paste or photo.\n$e';
        });
      }
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 750), (_) {
      unawaited(_captureAndScan());
    });
  }

  Future<void> _closeCamera() async {
    _poll?.cancel();
    _poll = null;
    final c = _camera;
    _camera = null;
    try {
      await c?.dispose();
    } catch (_) {}
  }

  Future<void> _captureAndScan() async {
    if (_handled || _busy || !mounted) return;
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (cam.value.isTakingPicture) return;

    _busy = true;
    XFile? shot;
    try {
      shot = await cam.takePicture();
      final path = shot.path;
      final codes = await _scanner.processImage(InputImage.fromFilePath(path));
      // Clean temp file
      try {
        await File(path).delete();
      } catch (_) {}

      if (codes.isEmpty) {
        if (mounted) {
          setState(() => _status = 'Scanning… keep QR steady and bright');
        }
        return;
      }
      for (final code in codes) {
        final raw = code.rawValue;
        if (raw != null && raw.isNotEmpty) {
          if (mounted) setState(() => _status = 'QR detected…');
          await _acceptRaw(raw);
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Still scanning…');
      }
    } finally {
      _busy = false;
    }
  }

  String? _extractId(String raw) {
    var id = raw.trim();
    final uri = RegExp(r'bitconnect://id/([0-9a-fA-F]+)').firstMatch(id);
    if (uri != null) id = uri.group(1)!;
    final hex = RegExp(r'([0-9a-fA-F]{64})').firstMatch(id);
    if (hex != null) id = hex.group(1)!;
    id = id.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    return id.length == 64 ? id : null;
  }

  Future<void> _acceptRaw(String raw) async {
    if (_handled) return;
    final id = _extractId(raw);
    if (id == null) {
      if (mounted) {
        setState(() => _status = 'QR found, but not a Bitconnect ID');
      }
      return;
    }
    _handled = true;
    _poll?.cancel();
    await widget.controller.addContact(
      Contact(name: 'scanned', netlessId: id),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact added')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _scanGallery() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (f == null) return;
      setState(() => _status = 'Reading photo…');
      final codes =
          await _scanner.processImage(InputImage.fromFilePath(f.path));
      if (codes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QR code in that photo')),
          );
        }
        return;
      }
      for (final c in codes) {
        if (c.rawValue != null) {
          await _acceptRaw(c.rawValue!);
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo scan failed: $e')),
        );
      }
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t == null || t.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clipboard empty')),
        );
      }
      return;
    }
    _manual.text = t;
    await _submitManual();
  }

  Future<void> _submitManual() async {
    final raw = _manual.text.trim();
    if (raw.isEmpty) return;
    final id = _extractId(raw);
    if (id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need a valid 64-character Bitconnect ID')),
        );
      }
      return;
    }
    await _acceptRaw(raw);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Bitconnect ID'),
        actions: [
          IconButton(
            tooltip: 'QR from gallery',
            onPressed: _scanGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            tooltip: 'Retry',
            onPressed: () async {
              await _closeAndReopen();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: Colors.orange.shade900.withValues(alpha: 0.9),
              child: ListTile(
                dense: true,
                title: Text(_error!, style: const TextStyle(fontSize: 12)),
                trailing: _permissionDenied
                    ? TextButton(
                        onPressed: openAppSettings, child: const Text('Settings'))
                    : null,
              ),
            ),
          if (_status != null && _error == null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.qr_code_scanner,
                  color: AppTheme.brandGreen, size: 18),
              title: Text(_status!, style: const TextStyle(fontSize: 12)),
            ),
          Expanded(
            child: _starting
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.brandGreen),
                  )
                : cam != null && cam.value.isInitialized
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(cam),
                          Center(
                            child: Container(
                              width: 260,
                              height: 260,
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: AppTheme.brandGreen, width: 3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                          const Positioned(
                            left: 12,
                            right: 12,
                            bottom: 12,
                            child: Text(
                              'Fill the green box with the QR code\n'
                              'Scanning takes a photo every ~0.75s',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 6),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Camera unavailable',
                                style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: _scanGallery,
                              child: const Text('Pick QR photo'),
                            ),
                          ],
                        ),
                      ),
          ),
          Material(
            color: AppTheme.card,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Or paste Bitconnect ID',
                        style: TextStyle(fontSize: 12, color: Colors.white60)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manual,
                      maxLines: 2,
                      style:
                          const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'bitconnect://id/… or 64 hex chars',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _paste,
                            icon: const Icon(Icons.content_paste, size: 18),
                            label: const Text('Paste'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: _submitManual,
                            child: const Text('Add contact'),
                          ),
                        ),
                      ],
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

  Future<void> _closeAndReopen() async {
    await _closeCamera();
    await _openCamera();
  }
}
