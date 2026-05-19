import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:graduabjj/api/competition_repo.dart';
import 'package:graduabjj/api/dto/competition_dto.dart';
import 'package:graduabjj/api/dto/upload_dto.dart';
import 'package:graduabjj/api/uploads_repo.dart';
import 'package:graduabjj/models/competition_photo.dart';
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

  /// Repositório tatami de competições (para fotos).
  final CompetitionRemoteRepo competitionRepo;

  /// Repositório tatami de uploads (para signed URL + PUT + confirm).
  final UploadsRemoteRepo uploadsRepo;

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
    required this.competitionRepo,
    required this.uploadsRepo,
  });

  @override
  State<CompetitionGallery> createState() => _CompetitionGalleryState();
}

class _CompetitionGalleryState extends State<CompetitionGallery> {
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
      final page = await widget.competitionRepo.listPhotos(
        widget.academyId,
        widget.competitionId,
        limit: 200,
      );

      if (mounted) {
        setState(() {
          _photos = page.items.map(CompetitionPhoto.fromApi).toList();
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
        final page = await widget.competitionRepo.listPhotos(
          widget.academyId,
          widget.competitionId,
          studentId: widget.studentId,
          limit: 200,
        );

        if (mounted) {
          setState(() => _photoCount = page.items.length);
        }
      } catch (e) {
        // Ignora erros de contagem
      }
    }
  }

  String _uploadPhotoType = 'student';

  Future<void> _handleUpload(File file, String? caption) async {
    final isTeam = _uploadPhotoType == 'team';
    final uploadStudentId = isTeam
        ? '__team__'
        : (widget.isAdmin ? _selectedStudentId : widget.studentId);
    final uploadStudentName = isTeam
        ? 'Equipe'
        : (widget.isAdmin
            ? widget.enrolledStudents
                .where((s) => s.id == _selectedStudentId)
                .map((s) => s.name)
                .firstOrNull
            : widget.studentName);

    if (uploadStudentId == null ||
        uploadStudentId.isEmpty ||
        uploadStudentName == null) {
      return;
    }

    try {
      // Etapa 1: determinar contentType pela extensão do arquivo.
      final pathLower = file.path.toLowerCase();
      final contentType = pathLower.endsWith('.png') ? 'image/png' : 'image/jpeg';
      final filename = file.path.split(Platform.pathSeparator).last;

      // Etapa 2: ler bytes.
      final Uint8List bytes = await file.readAsBytes();

      // Etapa 3: sign → PUT → finalize via uploadsRepo.
      final uploadedFile = await widget.uploadsRepo.uploadFile(
        purpose: ApiUploadPurpose.competitionPhoto,
        filename: filename,
        contentType: contentType,
        bytes: bytes,
        academyId: widget.academyId,
      );

      // Etapa 4: confirmar foto no contexto de competição.
      await widget.competitionRepo.createPhoto(
        widget.academyId,
        widget.competitionId,
        CreatePhotoRequest(
          url: uploadedFile.publicUrl ?? uploadedFile.internalPath,
          storagePath: uploadedFile.internalPath,
          studentId: uploadStudentId == '__team__' ? null : uploadStudentId,
          caption: caption,
        ),
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
        content: const Text(
            'Tem certeza que deseja deletar esta foto? Esta ação não pode ser desfeita.'),
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
      // TODO(tatami): API não tem DELETE /photos/{id} exposto ainda.
      // Quando o endpoint for adicionado ao CompetitionRemoteRepo,
      // substituir este bloco por competitionRepo.deletePhoto(...).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Remoção de fotos não disponível ainda.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _showUploadSheet() {
    setState(() {
      _selectedStudentId = '';
      _uploadPhotoType = 'student';
    });
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
          photoType: _uploadPhotoType,
          onPhotoTypeChange: (type) {
            setState(() => _uploadPhotoType = type);
            setSheetState(() {});
          },
        ),
      ),
    );
  }

  List<CompetitionPhoto> get _filteredPhotos {
    if (_filterStudentId.isEmpty) return _photos;
    if (_filterStudentId == '__team__') {
      return _photos
          .where((p) => p.photoType == 'team' || p.studentId == '__team__')
          .toList();
    }
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
              initialValue: _filterStudentId.isEmpty ? null : _filterStudentId,
              decoration: const InputDecoration(
                labelText: 'Filtrar por Aluno',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('Todos')),
                const DropdownMenuItem<String?>(
                    value: '__team__', child: Text('Equipe')),
                ..._getFilterStudents()
                    .where((s) => s.id != '__team__')
                    .map((s) =>
                        DropdownMenuItem<String?>(value: s.id, child: Text(s.name))),
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
              // isOwner: verifica pelo createdBy (uploadedByUid no ApiPhoto).
              final isOwner = photo.createdBy.isNotEmpty;

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
