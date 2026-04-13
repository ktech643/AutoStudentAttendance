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
  Future<void> enrollStudent({
    required String studentId,
    required List<List<double>> embeddings,
    required List<double> qualityScores,
    String sourceType = 'enrollment_capture',
  });
}
