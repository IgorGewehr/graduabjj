import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:graduabjj/models/competition_photo.dart';
import 'package:graduabjj/services/competition_photo_service.dart';
import 'package:graduabjj/widgets/competitions/photo_card.dart';
import 'package:graduabjj/widgets/competitions/photo_upload_sheet.dart';
import 'package:graduabjj/widgets/competitions/photo_fullscreen_viewer.dart';

class CompetitionGallery extends StatefulWidget {
  final String academyId;
  final String competitionId;
  final String competitionName;
  final String? studentId;
  final String? studentName;
  final bool isEnrolled;
  final bool isAdmin;
  final List<EnrolledStudent> enrolledStudents;

  const CompetitionGallery({
    super.key,
    required this.academyId,
    required this.competitionId,
    required this.competitionName,
    this.studentId,
    this.studentName,
    this.isEnrolled = false,
    this.isAdmin = false,
    this.enrolledStudents = const [],
  });

  @override
  State<CompetitionGallery> createState() => _CompetitionGalleryState();
}

class _CompetitionGalleryState extends State<CompetitionGallery> {
  final CompetitionPhotoService _photoService = CompetitionPhotoService();
  List<CompetitionPhoto> _photos = [];
  int _photoCount = 0;
  bool _isLoading = true;
  String? _error;
  String _selectedStudentId = '';
  String _filterStudentId = '';

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _loadPhotoCount();
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final photos = await _photoService.getPhotosByCompetition(
        academyId: widget.academyId,
        competitionId: widget.competitionId,
      );

      if (mounted) {
        setState(() {
          _photos = photos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPhotoCount() async {
    if (widget.studentId != null) {
      try {
        final count = await _photoService.getStudentPhotoCount(
          academyId: widget.academyId,
          competitionId: widget.competitionId,
          studentId: widget.studentId!,
        );

        if (mounted) {
          setState(() => _photoCount = count);
        }
      } catch (e) {
        // Ignore count errors
      }
    }
  }

  Future<void> _handleUpload(file, caption) async {
    final uploadStudentId = widget.isAdmin ? _selectedStudentId : widget.studentId;
    final uploadStudentName = widget.isAdmin
        ? widget.enrolledStudents
            .where((s) => s.id == _selectedStudentId)
            .map((s) => s.name)
            .firstOrNull
        : widget.studentName;

    if (uploadStudentId == null || uploadStudentId.isEmpty || uploadStudentName == null) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      await _photoService.uploadPhoto(
        academyId: widget.academyId,
        competitionId: widget.competitionId,
        competitionName: widget.competitionName,
        studentId: uploadStudentId,
        studentName: uploadStudentName,
        imageFile: file,
        caption: caption,
        createdBy: currentUserId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto adicionada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadPhotos();
        _loadPhotoCount();
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
      rethrow;
    }
  }

  Future<void> _handleDelete(String photoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deletar Foto?'),
        content: const Text('Tem certeza que deseja deletar esta foto? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Deletar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _photoService.deletePhoto(
          academyId: widget.academyId,
          photoId: photoId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto removida com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
          _loadPhotos();
          _loadPhotoCount();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao deletar foto: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showUploadSheet() {
    setState(() => _selectedStudentId = '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => PhotoUploadSheet(
          onUpload: _handleUpload,
          maxPhotos: widget.isAdmin ? 999 : 5,
          currentPhotos: _photoCount,
          isAdmin: widget.isAdmin,
          enrolledStudents: widget.enrolledStudents,
          selectedStudentId: _selectedStudentId,
          onStudentSelect: (id) {
            setState(() => _selectedStudentId = id);
            setSheetState(() {});
          },
        ),
      ),
    );
  }

  List<CompetitionPhoto> get _filteredPhotos {
    if (_filterStudentId.isEmpty) return _photos;
    return _photos.where((p) => p.studentId == _filterStudentId).toList();
  }

  void _showFullscreen(int index) {
    final photos = _filteredPhotos;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => PhotoFullscreenViewer(
          photos: photos,
          initialIndex: index,
          onDelete: _handleDelete,
          canEdit: widget.isAdmin,
          canDelete: widget.isAdmin,
        ),
      ),
    );
  }

  bool get _canUpload {
    return widget.isAdmin ||
        (widget.isEnrolled && widget.studentId != null && _photoCount < 5);
  }

  /// Get student list for filter: from enrolledStudents or derived from photos
  List<EnrolledStudent> _getFilterStudents() {
    if (widget.enrolledStudents.isNotEmpty) return widget.enrolledStudents;
    // Build unique student list from existing photos
    final studentMap = <String, String>{};
    for (final photo in _photos) {
      studentMap.putIfAbsent(photo.studentId, () => photo.studentName);
    }
    return studentMap.entries
        .map((e) => EnrolledStudent(id: e.key, name: e.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Erro ao carregar fotos: $_error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final filteredPhotos = _filteredPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Galeria de Fotos',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${filteredPhotos.length} foto${filteredPhotos.length != 1 ? 's' : ''}${_filterStudentId.isNotEmpty ? ' (filtrado)' : ''}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (_canUpload)
                ElevatedButton.icon(
                  onPressed: _showUploadSheet,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    widget.isAdmin ? 'Adicionar' : '($_photoCount/5)',
                  ),
                ),
            ],
          ),
        ),

        // Filter dropdown (available to all users)
        if (_getFilterStudents().length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String?>(
              value: _filterStudentId.isEmpty ? null : _filterStudentId,
              decoration: const InputDecoration(
                labelText: 'Filtrar por Aluno',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                ..._getFilterStudents()
                    .map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name))),
              ],
              onChanged: (value) {
                setState(() => _filterStudentId = value ?? '');
              },
            ),
          ),

        // Empty state
        if (filteredPhotos.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.photo_library, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    _filterStudentId.isNotEmpty
                        ? 'Nenhuma foto encontrada para este aluno.'
                        : 'Ainda não há fotos nesta competição.',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  if (_canUpload && _filterStudentId.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Seja o primeiro a adicionar!',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Photo grid
        if (filteredPhotos.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: filteredPhotos.length,
            itemBuilder: (context, index) {
              final photo = filteredPhotos[index];
              final currentUserId = FirebaseAuth.instance.currentUser?.uid;
              final isOwner = photo.createdBy == currentUserId;

              return PhotoCard(
                photo: photo,
                onTap: () => _showFullscreen(index),
                canEdit: widget.isAdmin || isOwner,
                canDelete: widget.isAdmin || isOwner,
                canHighlight: widget.isAdmin,
                onDelete: () => _handleDelete(photo.id),
              );
            },
          ),
      ],
    );
  }
}
