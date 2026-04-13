import 'dart:typed_data';

import '../../core/models/student.dart';

abstract class StudentRepository {
  Future<List<Student>> fetchStudents({String? search});
  Future<Student> createStudent({
    required String fullName,
    required String className,
    required String section,
    String? externalId,
    String? rollNumber,
    bool isActive = true,
  });
  Future<Student> updateStudent(Student student);

  /// Enroll a student with face data.
  ///
  /// - [embeddings]  : on-device embedding vectors (our FastAPI backend).
  /// - [jpegImages]  : raw JPEG bytes to upload (Docker InsightFace backend).
  /// - [studentName] / [className] : required by Docker's /enroll multipart form.
  ///
  /// Implementations should prefer [jpegImages] when provided, falling back to
  /// [embeddings] for the custom FastAPI backend.
  Future<void> enrollStudent({
    required String studentId,
    required List<List<double>> embeddings,
    required List<double> qualityScores,
    String sourceType = 'enrollment_capture',
    List<Uint8List>? jpegImages,
    String? studentName,
    String? className,
  });

  /// Returns all enrolled embeddings from the server in the format expected
  /// by the native recognition plugin's loadEnrolledEmbeddings channel method.
  /// Keys per item: studentId, studentName, rollNumber, vector.
  /// Returns an empty list when the backend does not support this (e.g. Docker).
  Future<List<Map<String, dynamic>>> fetchAllEmbeddingsForDevice();
}
