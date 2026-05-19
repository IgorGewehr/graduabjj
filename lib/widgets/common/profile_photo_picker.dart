import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/dto/upload_dto.dart';
import '../../api/repositories.dart';
import '../../core/theme.dart';
import 'image_crop_screen.dart';

/// Widget for displaying and picking student profile photos
class ProfilePhotoPicker extends ConsumerStatefulWidget {
  final String academyId;
  final String studentId;
  final String? photoUrl;
  final String fullName;
  final String currentBelt;
  final bool editable;
  final double size;
  final VoidCallback? onPhotoUpdated;

  const ProfilePhotoPicker({
    Key? key,
    required this.academyId,
    required this.studentId,
    this.photoUrl,
    required this.fullName,
    required this.currentBelt,
    this.editable = false,
    this.size = 80.0,
    this.onPhotoUpdated,
  }) : super(key: key);

  @override
  ConsumerState<ProfilePhotoPicker> createState() => _ProfilePhotoPickerState();
}

class _ProfilePhotoPickerState extends ConsumerState<ProfilePhotoPicker> {
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  /// Get initials from name
  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  /// Show image source selection bottom sheet
  Future<ImageSource?> _showImageSourceSheet() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Selecionar Foto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Câmera'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeria'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Show confirmation bottom sheet with image preview
  Future<bool?> _showPhotoConfirmation(File imageFile) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Confirmar Foto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: Image.file(
                  imageFile,
                  height: 200,
                  width: 200,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Confirmar'),
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

  /// Pick image from gallery/camera and crop
  Future<void> _pickAndCropImage() async {
    try {
      // Show source selection
      final source = await _showImageSourceSheet();
      if (source == null) return;

      // Pick image
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Crop image using custom screen with buttons at the bottom
      if (!mounted) return;
      final File? croppedFile = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => ImageCropScreen(
            imageFile: File(pickedFile.path),
          ),
        ),
      );

      if (croppedFile == null) return;

      // Show confirmation bottom sheet with preview
      if (!mounted) return;
      final confirmed = await _showPhotoConfirmation(croppedFile);
      if (confirmed != true) return;

      // Upload cropped image via tatami uploads (sign → PUT GCS → finalize)
      setState(() => _uploading = true);

      await ref.read(uploadsRepoProvider).uploadFileFromDisk(
        purpose: ApiUploadPurpose.studentPhoto,
        file: croppedFile,
        contentType: 'image/jpeg',
        academyId: widget.academyId,
        targetId: widget.studentId,
      );

      if (mounted) {
        setState(() => _uploading = false);
        widget.onPhotoUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto atualizada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Delete photo
  Future<void> _deletePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Foto'),
        content: const Text('Tem certeza que deseja remover a foto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // TODO(tatami): tatami não expõe endpoint DELETE /v1/uploads/{fileId}
    // ainda. Exibir mensagem de não suportado até o endpoint existir.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remoção de foto ainda não suportada. Contate o suporte.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final beltColor = AppTheme.getBeltColor(widget.currentBelt);
    final isWhiteBelt = widget.currentBelt == 'white';

    return Stack(
      children: [
        // Avatar
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: beltColor, width: 3),
          ),
          child: GestureDetector(
            onTap: widget.editable ? _pickAndCropImage : null,
            child: CircleAvatar(
              radius: widget.size / 2 - 3,
              backgroundColor: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                  ? Colors.transparent
                  : beltColor,
              foregroundImage: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(widget.photoUrl!)
                  : null,
              child: widget.photoUrl == null || widget.photoUrl!.isEmpty
                  ? Text(
                      _getInitials(widget.fullName),
                      style: TextStyle(
                        fontSize: widget.size / 3,
                        fontWeight: FontWeight.w600,
                        color: isWhiteBelt ? Colors.black : Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ),

        // Camera icon (editable mode)
        if (widget.editable)
          Positioned(
            bottom: 0,
            right: 0,
            child: Row(
              children: [
                GestureDetector(
                  onTap: _uploading ? null : _pickAndCropImage,
                  child: Container(
                    width: widget.size * 0.3,
                    height: widget.size * 0.3,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: widget.size * 0.15,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
                  const SizedBox(width: 4),
                if (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
                  GestureDetector(
                    onTap: _uploading ? null : _deletePhoto,
                    child: Container(
                      width: widget.size * 0.3,
                      height: widget.size * 0.3,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.delete,
                        size: widget.size * 0.15,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // Loading overlay
        if (_uploading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: widget.size * 0.05,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
