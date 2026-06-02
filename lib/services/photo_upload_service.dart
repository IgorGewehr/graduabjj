import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for uploading and managing student profile photos
class PhotoUploadService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Upload a student profile photo
  ///
  /// - [academyId]: Academy ID
  /// - [studentId]: Student ID
  /// - [imageFile]: Image file to upload (already cropped)
  ///
  /// Returns the download URL of the uploaded photo
  Future<String> uploadStudentPhoto({
    required String academyId,
    required String studentId,
    required File imageFile,
  }) async {
    try {
      // Validate file exists
      if (!await imageFile.exists()) {
        throw Exception('Arquivo de imagem não encontrado');
      }

      // Get file size
      final fileSize = await imageFile.length();

      // Validate size (5MB max)
      const maxSize = 5 * 1024 * 1024; // 5MB
      if (fileSize > maxSize) {
        throw Exception('Imagem muito grande. Tamanho máximo: 5MB.');
      }

      // Storage path
      final storagePath = 'academies/$academyId/students/$studentId/profile.jpg';
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

      // Update Firestore
      await _updateStudentPhotoUrl(
        academyId: academyId,
        studentId: studentId,
        photoUrl: downloadURL,
      );

      return downloadURL;
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized') {
        throw Exception('Você não tem permissão para alterar esta foto.');
      } else if (e.code == 'quota-exceeded') {
        throw Exception('Limite de armazenamento excedido.');
      }
      throw Exception('Erro ao enviar foto: ${e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro ao enviar foto: $e');
    }
  }

  /// Delete a student profile photo
  ///
  /// - [academyId]: Academy ID
  /// - [studentId]: Student ID
  Future<void> deleteStudentPhoto({
    required String academyId,
    required String studentId,
  }) async {
    try {
      // Storage path
      final storagePath = 'academies/$academyId/students/$studentId/profile.jpg';
      final storageRef = _storage.ref().child(storagePath);

      // Try to delete (ignore if doesn't exist)
      try {
        await storageRef.delete();
      } on FirebaseException catch (e) {
        // Ignore if file doesn't exist
        if (e.code != 'object-not-found') {
          rethrow;
        }
      }

      // Update Firestore
      await _updateStudentPhotoUrl(
        academyId: academyId,
        studentId: studentId,
        photoUrl: '',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized') {
        throw Exception('Você não tem permissão para remover esta foto.');
      }
      throw Exception('Erro ao remover foto: ${e.message}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Erro ao remover foto: $e');
    }
  }

  /// Update student photoUrl in Firestore
  Future<void> _updateStudentPhotoUrl({
    required String academyId,
    required String studentId,
    required String photoUrl,
  }) async {
    final docRef = _firestore
        .collection('academies')
        .doc(academyId)
        .collection('students')
        .doc(studentId);

    await docRef.update({
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Uploads a PRIVATE evolution photo for a physical assessment.
  /// Path: academies/{id}/students/{sid}/assessments/{angle}_{ts}.jpg
  /// (storage.rules restrict read to staff + the student). Returns the download
  /// URL + the storage path (both stored on the assessment doc).
  Future<({String url, String storagePath})> uploadAssessmentPhoto({
    required String academyId,
    required String studentId,
    required File imageFile,
    required String angle,
  }) async {
    if (!await imageFile.exists()) {
      throw Exception('Arquivo de imagem não encontrado');
    }
    final fileSize = await imageFile.length();
    const maxSize = 10 * 1024 * 1024; // 10MB
    if (fileSize > maxSize) {
      throw Exception('Imagem muito grande. Tamanho máximo: 10MB.');
    }

    final ts = DateTime.now().microsecondsSinceEpoch;
    final storagePath =
        'academies/$academyId/students/$studentId/assessments/${angle}_$ts.jpg';
    final ref = _storage.ref().child(storagePath);
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'private, max-age=3600',
    );
    try {
      final snapshot = await ref.putFile(imageFile, metadata);
      final url = await snapshot.ref.getDownloadURL();
      return (url: url, storagePath: storagePath);
    } on FirebaseException catch (e) {
      if (e.code == 'unauthorized') {
        throw Exception('Você não tem permissão para enviar esta foto.');
      }
      throw Exception('Erro ao enviar foto: ${e.message}');
    }
  }

  /// Deletes an assessment photo by its storage path (best-effort).
  Future<void> deleteAssessmentPhoto({required String storagePath}) async {
    try {
      await _storage.ref().child(storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}
