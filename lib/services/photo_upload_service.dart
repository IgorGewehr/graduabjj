import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

import '../api/dto/student_dto.dart';
import '../api/student_repo.dart';

/// Service for uploading and managing student profile photos
class PhotoUploadService {
  PhotoUploadService({required StudentRemoteRepo studentRepo})
      : _studentRepo = studentRepo;

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final StudentRemoteRepo _studentRepo;

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

      // Update student record via Tatami REST API
      await _studentRepo.update(
        academyId,
        studentId,
        UpdateStudentRequest(photoUrl: downloadURL),
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

      // Clear photoUrl via Tatami REST API
      await _studentRepo.update(
        academyId,
        studentId,
        const UpdateStudentRequest(photoUrl: ''),
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
}
