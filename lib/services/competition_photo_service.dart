import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:graduabjj/models/competition_photo.dart';

/// Service for uploading and managing competition photos
class CompetitionPhotoService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Upload a competition photo
  ///
  /// - [academyId]: Academy ID
  /// - [competitionId]: Competition ID
  /// - [competitionName]: Competition name (denormalized)
  /// - [studentId]: Student ID (who uploaded)
  /// - [studentName]: Student name (denormalized)
  /// - [imageFile]: Image file to upload
  /// - [caption]: Optional caption (max 200 chars)
  /// - [createdBy]: User ID who uploaded
  /// - [medalType]: Optional medal type
  ///
  /// Returns the created CompetitionPhoto
  Future<CompetitionPhoto> uploadPhoto({
    required String academyId,
    required String competitionId,
    required String competitionName,
    required String studentId,
    required String studentName,
    required File imageFile,
    String? caption,
    required String createdBy,
    CompetitionPosition? medalType,
  }) async {
    try {
      // Validate file exists
      if (!await imageFile.exists()) {
        throw Exception('Arquivo de imagem não encontrado');
      }

      // Get file size
      final fileSize = await imageFile.length();

      // Validate size (10MB max for competition photos)
      const maxSize = 10 * 1024 * 1024; // 10MB
      if (fileSize > maxSize) {
        throw Exception('Imagem muito grande. Tamanho máximo: 10MB.');
      }

      // Validate caption length
      if (caption != null && caption.length > 200) {
        throw Exception('Legenda muito longa. Máximo: 200 caracteres.');
      }

      // Generate unique photo ID
      final photoId = _firestore.collection('temp').doc().id;

      // Storage path
      final storagePath =
          'academies/$academyId/competitions/$competitionId/photos/$photoId.jpg';
      final storageRef = _storage.ref().child(storagePath);

      // Upload metadata
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=3600, must-revalidate',
      );

      // Upload file
      final uploadTask = storageRef.putFile(imageFile, metadata);

      // Wait for completion
      final snapshot = await uploadTask;

      // Get download URL
      final downloadURL = await snapshot.ref.getDownloadURL();

      // Create Firestore document
      final photoData = {
        'competitionId': competitionId,
        'competitionName': competitionName,
        'studentId': studentId,
        'studentName': studentName,
        'url': downloadURL,
        'storagePath': storagePath,
        'caption': caption,
        'likes': 0,
        'isHighlight': false,
        'medalType': medalType?.value,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
      };

      final docRef = _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .doc(photoId);

      await docRef.set(photoData);

      // Get created document
      final photoDoc = await docRef.get();
      return CompetitionPhoto.fromFirestore(photoDoc);
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw Exception('Você não tem permissão para fazer upload.');
      } else if (e.code == 'quota-exceeded') {
        throw Exception('Limite de armazenamento excedido.');
      }
      throw Exception('Erro ao enviar foto: ${e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro ao enviar foto: $e');
    }
  }

  /// Get photos by competition
  Future<List<CompetitionPhoto>> getPhotosByCompetition({
    required String academyId,
    required String competitionId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .where('competitionId', isEqualTo: competitionId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => CompetitionPhoto.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Erro ao carregar fotos: $e');
    }
  }

  /// Get photos by student
  Future<List<CompetitionPhoto>> getPhotosByStudent({
    required String academyId,
    required String studentId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .where('studentId', isEqualTo: studentId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => CompetitionPhoto.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Erro ao carregar fotos: $e');
    }
  }

  /// Get student photo count for a competition
  Future<int> getStudentPhotoCount({
    required String academyId,
    required String competitionId,
    required String studentId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .where('competitionId', isEqualTo: competitionId)
          .where('studentId', isEqualTo: studentId)
          .get();

      return snapshot.size;
    } catch (e) {
      throw Exception('Erro ao contar fotos: $e');
    }
  }

  /// Update photo caption
  Future<void> updatePhotoCaption({
    required String academyId,
    required String photoId,
    required String caption,
  }) async {
    try {
      if (caption.length > 200) {
        throw Exception('Legenda muito longa. Máximo: 200 caracteres.');
      }

      final docRef = _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .doc(photoId);

      await docRef.update({
        'caption': caption,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw Exception('Você não tem permissão para editar esta foto.');
      }
      throw Exception('Erro ao atualizar legenda: ${e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro ao atualizar legenda: $e');
    }
  }

  /// Toggle highlight status (admin only)
  Future<void> toggleHighlight({
    required String academyId,
    required String photoId,
    required bool isHighlight,
  }) async {
    try {
      final docRef = _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .doc(photoId);

      await docRef.update({
        'isHighlight': isHighlight,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw Exception('Você não tem permissão para marcar destaques.');
      }
      throw Exception('Erro ao atualizar destaque: ${e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro ao atualizar destaque: $e');
    }
  }

  /// Delete photo
  Future<void> deletePhoto({
    required String academyId,
    required String photoId,
  }) async {
    try {
      // Get photo document
      final docRef = _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .doc(photoId);

      final photoDoc = await docRef.get();

      if (!photoDoc.exists) {
        throw Exception('Foto não encontrada.');
      }

      final photo = CompetitionPhoto.fromFirestore(photoDoc);

      // Delete from Storage
      try {
        final storageRef = _storage.ref().child(photo.storagePath);
        await storageRef.delete();
      } on FirebaseException catch (e) {
        // Ignore if file doesn't exist
        if (e.code != 'object-not-found') {
          rethrow;
        }
      }

      // Delete from Firestore
      await docRef.delete();
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized' || e.code == 'permission-denied') {
        throw Exception('Você não tem permissão para deletar esta foto.');
      }
      throw Exception('Erro ao deletar foto: ${e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro ao deletar foto: $e');
    }
  }

  /// Get photo by ID
  Future<CompetitionPhoto?> getPhotoById({
    required String academyId,
    required String photoId,
  }) async {
    try {
      final docRef = _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .doc(photoId);

      final photoDoc = await docRef.get();

      if (!photoDoc.exists) {
        return null;
      }

      return CompetitionPhoto.fromFirestore(photoDoc);
    } catch (e) {
      throw Exception('Erro ao carregar foto: $e');
    }
  }

  /// Get highlight photos (for competition cover)
  Future<List<CompetitionPhoto>> getHighlightPhotos({
    required String academyId,
    required String competitionId,
    int limit = 10,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .where('competitionId', isEqualTo: competitionId)
          .where('isHighlight', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => CompetitionPhoto.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Erro ao carregar fotos em destaque: $e');
    }
  }

  /// Get photos by student and competition
  Future<List<CompetitionPhoto>> getPhotosByStudentAndCompetition({
    required String academyId,
    required String studentId,
    required String competitionId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .where('studentId', isEqualTo: studentId)
          .where('competitionId', isEqualTo: competitionId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => CompetitionPhoto.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Erro ao carregar fotos: $e');
    }
  }

  /// Get all photos (for admin gallery view)
  Future<List<CompetitionPhoto>> getAllPhotos({
    required String academyId,
    int? limit,
  }) async {
    try {
      var query = _firestore
          .collection('academies')
          .doc(academyId)
          .collection('competitionPhotos')
          .orderBy('createdAt', descending: true);

      if (limit != null) {
        query = query.limit(limit);
      }

      final snapshot = await query.get();

      return snapshot.docs
          .map((doc) => CompetitionPhoto.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Erro ao carregar fotos: $e');
    }
  }

  /// Stream photos by competition (real-time updates)
  Stream<List<CompetitionPhoto>> streamPhotosByCompetition({
    required String academyId,
    required String competitionId,
  }) {
    return _firestore
        .collection('academies')
        .doc(academyId)
        .collection('competitionPhotos')
        .where('competitionId', isEqualTo: competitionId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CompetitionPhoto.fromFirestore(doc))
            .toList());
  }
}
