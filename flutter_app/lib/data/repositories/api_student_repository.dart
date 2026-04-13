import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/models/student.dart';
import '../services/api_client.dart';
import 'student_repository.dart';

class ApiStudentRepository implements StudentRepository {
  ApiStudentRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<Student>> fetchStudents({String? search}) async {
    final response = await _apiClient.dio.get<dynamic>(
      '/students',
      queryParameters: search == null ? null : {'search': search},
    );
    final data = response.data;

    // Our FastAPI returns a plain JSON array.
    // Docker AttendX returns { "total": N, "students": [...] }.
    List<dynamic> list;
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['students'] as List<dynamic>?) ?? [];
    } else {
      list = [];
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map(Student.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Student> createStudent({
    required String fullName,
    required String className,
    required String section,
    String? externalId,
    String? rollNumber,
    bool isActive = true,
  }) async {
    // Try our FastAPI first (POST /students).
    // Docker has no create-student endpoint — return a synthetic Student so the
    // UI can continue to the capture step; the real creation happens in enrollStudent().
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/students',
        data: {
          'full_name': fullName,
          'class_name': className,
          'section': section,
          'external_id': externalId,
          'roll_number': rollNumber,
          'is_active': isActive,
        },
      );
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300 &&
          response.data != null) {
        return Student.fromJson(response.data!);
      }
    } catch (_) {
      // Fall through to synthetic student for Docker.
    }

    // Docker-compatible synthetic student — ID is the roll number (or name slug).
    final id = (rollNumber?.isNotEmpty == true)
        ? rollNumber!
        : fullName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return Student(
      id: id,
      fullName: fullName,
      className: className,
      section: section,
      rollNumber: rollNumber,
      externalId: externalId,
      isActive: isActive,
    );
  }

  @override
  Future<Student> updateStudent(Student student) async {
    try {
      final response = await _apiClient.dio.put<Map<String, dynamic>>(
        '/students/${student.id}',
        data: {
          'external_id': student.externalId,
          'roll_number': student.rollNumber,
          'full_name': student.fullName,
          'class_name': student.className,
          'section': student.section,
          'is_active': student.isActive,
        },
      );
      if (response.data != null) return Student.fromJson(response.data!);
    } catch (_) {}
    return student;
  }

  @override
  Future<void> enrollStudent({
    required String studentId,
    required List<List<double>> embeddings,
    required List<double> qualityScores,
    String sourceType = 'enrollment_capture',
    List<Uint8List>? jpegImages,
    String? studentName,
    String? className,
  }) async {
    if (jpegImages != null && jpegImages.isNotEmpty) {
      // Docker AttendX: multipart form upload — server extracts InsightFace embeddings.
      final formData = FormData.fromMap({
        'student_id': studentId,
        'name': studentName ?? studentId,
        'class_name': className ?? '',
        'images': jpegImages
            .map((bytes) => MultipartFile.fromBytes(
                  bytes,
                  filename: 'face.jpg',
                  contentType: DioMediaType('image', 'jpeg'),
                ))
            .toList(),
      });
      await _apiClient.dio.post<void>('/enroll', data: formData);
      return;
    }

    // Our FastAPI: JSON embedding vectors.
    await _apiClient.dio.post<void>(
      '/students/$studentId/enroll',
      data: {
        'source_type': sourceType,
        'embeddings': embeddings,
        'quality_scores': qualityScores,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAllEmbeddingsForDevice() async {
    try {
      final response = await _apiClient.dio.get<List<dynamic>>('/embeddings/all');
      final items = response.data ?? const [];
      return items.whereType<Map<dynamic, dynamic>>().map((raw) {
        final item = raw.map((k, v) => MapEntry(k.toString(), v));
        final vectorRaw = item['vector'] as List<dynamic>? ?? const [];
        return <String, dynamic>{
          'studentId': item['student_id'] as String? ?? '',
          'studentName': item['student_name'] as String? ?? '',
          'rollNumber': item['roll_number'] as String? ?? '',
          'vector': vectorRaw
              .map((v) => (v as num).toDouble())
              .toList(growable: false),
        };
      }).toList(growable: false);
    } catch (_) {
      // Docker does not expose raw embeddings — server-side recognition is used instead.
      return [];
    }
  }
}
