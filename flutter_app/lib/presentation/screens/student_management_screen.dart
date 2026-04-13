import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/student.dart';
import '../../data/repositories/student_repository.dart';
import '../providers/providers.dart';

class StudentManagementScreen extends ConsumerStatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  ConsumerState<StudentManagementScreen> createState() => _StudentManagementScreenState();
}

class _StudentManagementScreenState extends ConsumerState<StudentManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(studentRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Student Management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddStudentDialog(repository),
        icon: const Icon(Icons.person_add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name / roll / external ID',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => setState(() => _searchTerm = value.trim()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Student>>(
              future: repository.fetchStudents(search: _searchTerm.isEmpty ? null : _searchTerm),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final students = snapshot.data!;
                if (students.isEmpty) {
                  return const Center(child: Text('No students found'));
                }
                return ListView.separated(
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final student = students[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(student.fullName.isNotEmpty ? student.fullName[0] : '?'),
                      ),
                      title: Text(student.fullName),
                      subtitle: Text(
                        '${student.className}-${student.section} | Photos: ${student.embeddingCount} | ${student.rollNumber ?? '-'}',
                      ),
                      trailing: Switch(
                        value: student.isActive,
                        onChanged: (value) async {
                          await repository.updateStudent(
                            Student(
                              id: student.id,
                              externalId: student.externalId,
                              rollNumber: student.rollNumber,
                              fullName: student.fullName,
                              className: student.className,
                              section: student.section,
                              isActive: value,
                              embeddingCount: student.embeddingCount,
                            ),
                          );
                          setState(() {});
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddStudentDialog(StudentRepository repository) async {
    final nameController = TextEditingController();
    final classController = TextEditingController();
    final sectionController = TextEditingController();
    final rollController = TextEditingController();
    final externalIdController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add student'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full name')),
                TextField(controller: classController, decoration: const InputDecoration(labelText: 'Class')),
                TextField(controller: sectionController, decoration: const InputDecoration(labelText: 'Section')),
                TextField(controller: rollController, decoration: const InputDecoration(labelText: 'Roll number')),
                TextField(controller: externalIdController, decoration: const InputDecoration(labelText: 'External ID')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await repository.createStudent(
                  fullName: nameController.text.trim(),
                  className: classController.text.trim(),
                  section: sectionController.text.trim(),
                  rollNumber: rollController.text.trim().isEmpty ? null : rollController.text.trim(),
                  externalId: externalIdController.text.trim().isEmpty ? null : externalIdController.text.trim(),
                );
                if (mounted) {
                  Navigator.of(context).pop();
                  setState(() {});
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}
