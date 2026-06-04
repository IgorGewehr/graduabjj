import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';

/// Custom image crop screen with confirm/cancel buttons at the bottom.
class ImageCropScreen extends StatefulWidget {
  final File imageFile;

  const ImageCropScreen({super.key, required this.imageFile});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final _cropController = CropController();
  Uint8List? _imageData;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await widget.imageFile.readAsBytes();
    if (mounted) {
      setState(() => _imageData = bytes);
    }
  }

  Future<void> _onCropped(Uint8List croppedBytes) async {
    try {
      final tempFile = File(
        '${Directory.systemTemp.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(croppedBytes);
      if (mounted) {
        Navigator.pop(context, tempFile);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao processar imagem: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Footer padding must clear the bottom gesture/home indicator inset so the
    // primary action is always fully visible and tappable.
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      // AppBar respects the status bar automatically — the title and Cancel
      // action can never sit under the status bar icons.
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancelar',
          onPressed: _isCropping ? null : () => Navigator.pop(context),
        ),
        title: const Text(
          'Ajustar Foto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Crop area
          Expanded(
            child: _imageData != null
                ? Crop(
                    image: _imageData!,
                    controller: _cropController,
                    onCropped: _onCropped,
                    aspectRatio: 1,
                    withCircleUi: true,
                    baseColor: Colors.black,
                    maskColor: Colors.black.withValues(alpha: 0.7),
                    initialSize: 0.8,
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),

          // Footer action: always visible above the bottom system inset.
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _isCropping ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isCropping
                        ? null
                        : () {
                            setState(() => _isCropping = true);
                            _cropController.crop();
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isCropping
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Confirmar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
