import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/photo_upload_service.dart';
import '../../core/theme.dart';

/// Widget for displaying and picking student profile photos
class ProfilePhotoPicker extends StatefulWidget {
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
  State<ProfilePhotoPicker> createState() => _ProfilePhotoPickerState();
}

class _ProfilePhotoPickerState extends State<ProfilePhotoPicker> {
  final PhotoUploadService _uploadService = PhotoUploadService();
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  /// Get initials from name
  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  /// Pick image from gallery and crop
  Future<void> _pickAndCropImage() async {
    try {
      // Pick image from gallery
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Crop image
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
        compressFormat: ImageCompressFormat.jpg,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Ajustar Foto',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: Colors.blue,
            cropFrameColor: Colors.blue,
            cropGridColor: Colors.white.withOpacity(0.5),
            backgroundColor: Colors.black,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Ajustar Foto',
            doneButtonTitle: 'Confirmar',
            cancelButtonTitle: 'Cancelar',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (croppedFile == null) return;

      // Upload cropped image
      setState(() => _uploading = true);

      await _uploadService.uploadStudentPhoto(
        academyId: widget.academyId,
        studentId: widget.studentId,
        imageFile: File(croppedFile.path),
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

    try {
      setState(() => _uploading = true);

      await _uploadService.deleteStudentPhoto(
        academyId: widget.academyId,
        studentId: widget.studentId,
      );

      if (mounted) {
        setState(() => _uploading = false);
        widget.onPhotoUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto removida com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao remover foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
                          color: Colors.black.withOpacity(0.2),
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
                            color: Colors.black.withOpacity(0.2),
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
                color: Colors.black.withOpacity(0.5),
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
