import '../../core/models/student.dart';
import '../services/api_client.dart';
import 'student_repository.dart';

class ApiStudentRepository implements StudentRepository {
  ApiStudentRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Student> createStudent({
    required String fullName,
    required String className,
    required String section,
    String? externalId,
    String? rollNumber,
    bool isActive = true,
  }) async {
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
    return Student.fromJson(response.data!);
  }

  @override
  Future<List<Student>> fetchStudents({String? search}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/students',
      queryParameters: search == null ? null : {'search': search},
    );
    return response.data!
        .whereType<Map<String, dynamic>>()
        .map(Student.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Student> updateStudent(Student student) async {
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
    return Student.fromJson(response.data!);
  }

  @override
  Future<void> enrollStudent({
    required String studentId,
    required List<List<double>> embeddings,
    required List<double> qualityScores,
    String sourceType = 'enrollment_capture',
  }) async {
    await _apiClient.dio.post<void>(
      '/students/$studentId/enroll',
      data: {
        'source_type': sourceType,
        'embeddings': embeddings,
        'quality_scores': qualityScores,
      },
    );
  }
}
