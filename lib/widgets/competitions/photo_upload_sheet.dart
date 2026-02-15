import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EnrolledStudent {
  final String id;
  final String name;

  const EnrolledStudent({required this.id, required this.name});
}

class PhotoUploadSheet extends StatefulWidget {
  final Function(File file, String? caption) onUpload;
  final int maxPhotos;
  final int currentPhotos;
  final bool isAdmin;
  final List<EnrolledStudent> enrolledStudents;
  final String? selectedStudentId;
  final ValueChanged<String>? onStudentSelect;
  final String photoType;
  final ValueChanged<String>? onPhotoTypeChange;

  const PhotoUploadSheet({
    super.key,
    required this.onUpload,
    required this.maxPhotos,
    required this.currentPhotos,
    this.isAdmin = false,
    this.enrolledStudents = const [],
    this.selectedStudentId,
    this.onStudentSelect,
    this.photoType = 'student',
    this.onPhotoTypeChange,
  });

  @override
  State<PhotoUploadSheet> createState() => _PhotoUploadSheetState();
}

class _PhotoUploadSheetState extends State<PhotoUploadSheet> {
  File? _selectedImage;
  final TextEditingController _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  int get remainingPhotos => widget.maxPhotos - widget.currentPhotos;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        final file = File(image.path);
        final fileSize = await file.length();

        // Validate format (JPEG, PNG, WEBP only)
        final extension = image.path.toLowerCase().split('.').last;
        if (!['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Formato inválido. Use JPEG, PNG ou WEBP'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Validate size (10MB)
        if (fileSize > 10 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Imagem muito grande. Tamanho máximo: 10MB'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        setState(() {
          _selectedImage = file;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar imagem: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedImage == null) return;

    setState(() => _isUploading = true);

    try {
      final caption = _captionController.text.trim();
      await widget.onUpload(
        _selectedImage!,
        caption.isEmpty ? null : caption,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao fazer upload: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Row(
                  children: [
                    const Text(
                      'Adicionar Foto',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

              // Admin: photo type toggle + student selector
              if (widget.isAdmin) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'student', label: Text('Aluno')),
                    ButtonSegment(value: 'team', label: Text('Equipe')),
                  ],
                  selected: {widget.photoType},
                  onSelectionChanged: (Set<String> selected) {
                    widget.onPhotoTypeChange?.call(selected.first);
                  },
                ),
                const SizedBox(height: 16),
                if (widget.photoType == 'student' && widget.enrolledStudents.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value: widget.selectedStudentId?.isNotEmpty == true
                        ? widget.selectedStudentId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Selecione o Aluno',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.enrolledStudents
                        .map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        widget.onStudentSelect?.call(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ],

              // Photo counter
              if (remainingPhotos > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Você pode adicionar mais $remainingPhotos foto${remainingPhotos > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Limite de fotos atingido',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                ),

              // Image selection or preview
              if (_selectedImage == null)
                Column(
                  children: [
                    InkWell(
                      onTap: () => _pickImage(ImageSource.gallery),
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey[300]!,
                            width: 2,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_upload,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Toque para selecionar uma foto',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'JPG, PNG ou WEBP • Máx 10MB',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Câmera'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Galeria'),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    // Preview
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        height: 250,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Caption input
                    TextField(
                      controller: _captionController,
                      maxLength: 200,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Legenda (opcional)',
                        border: OutlineInputBorder(),
                        hintText: 'Adicione uma legenda...',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isUploading
                                ? null
                                : () {
                                    setState(() {
                                      _selectedImage = null;
                                      _captionController.clear();
                                    });
                                  },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isUploading ||
                                    (widget.isAdmin &&
                                        widget.photoType == 'student' &&
                                        (widget.selectedStudentId == null ||
                                            widget.selectedStudentId!.isEmpty))
                                ? null
                                : _handleUpload,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isUploading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text('Fazer Upload'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
