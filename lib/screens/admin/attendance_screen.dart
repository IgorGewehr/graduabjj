import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Admin Attendance Screen - Mark students present
class AdminAttendanceScreen extends ConsumerStatefulWidget {
  const AdminAttendanceScreen({super.key});

  @override
  ConsumerState<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends ConsumerState<AdminAttendanceScreen> {
  List<BJJClass> _classes = [];
  List<Student> _students = [];
  Set<String> _presentStudentIds = {};
  BJJClass? _selectedClass;
  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      final classService = ClassService(academyId);
      final studentService = StudentService(academyId);

      final classes = await classService.getTodayClasses();
      final students = await studentService.getActive();

      // Get current class
      final currentClass = await classService.getCurrentClass();

      setState(() {
        _classes = classes;
        _students = students;
        _selectedClass = currentClass ?? (classes.isNotEmpty ? classes.first : null);
        _isLoading = false;
      });

      if (_selectedClass != null) {
        _loadAttendanceForClass();
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAttendanceForClass() async {
    if (_selectedClass == null) return;

    try {
      final academyId = FirebaseService.academyId;
      final attendanceService = AttendanceService(academyId);

      final todayAttendance = await attendanceService.getByDateAndClass(
        DateTime.now(),
        _selectedClass!.id,
      );

      setState(() {
        _presentStudentIds = todayAttendance.map((a) => a.studentId).toSet();
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _toggleAttendance(Student student) async {
    if (_selectedClass == null || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final academyId = FirebaseService.academyId;
      final attendanceService = AttendanceService(academyId);

      final wasPresent = _presentStudentIds.contains(student.id);

      if (wasPresent) {
        await attendanceService.unmarkPresent(
          student.id,
          _selectedClass!.id,
          DateTime.now(),
        );
        setState(() {
          _presentStudentIds.remove(student.id);
        });
      } else {
        await attendanceService.markPresent(
          studentId: student.id,
          studentName: student.fullName,
          classId: _selectedClass!.id,
          className: _selectedClass!.name,
          verifiedBy: 'admin', // TODO: Get actual admin ID
          verifiedByName: 'Administrador',
        );
        setState(() {
          _presentStudentIds.add(student.id);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chamada'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Class Selector
                _buildClassSelector(),

                // Date display
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(DateTime.now()),
                        style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_presentStudentIds.length} presente(s)',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar aluno...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Student List
                Expanded(
                  child: _selectedClass == null
                      ? _buildNoClassState()
                      : _buildStudentList(),
                ),
              ],
            ),
    );
  }

  Widget _buildClassSelector() {
    if (_classes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Turma',
            style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _classes.length,
              itemBuilder: (context, index) {
                final cls = _classes[index];
                final isSelected = _selectedClass?.id == cls.id;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cls.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedClass = cls);
                        _loadAttendanceForClass();
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoClassState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            'Nenhuma turma hoje',
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Não há turmas agendadas para hoje',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    var filteredStudents = _students;

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      filteredStudents = filteredStudents.where((s) =>
          s.fullName.toLowerCase().contains(_searchQuery) ||
          (s.nickname?.toLowerCase().contains(_searchQuery) ?? false)
      ).toList();
    }

    // Filter by class students if class has specific students
    if (_selectedClass!.studentIds.isNotEmpty) {
      filteredStudents = filteredStudents.where((s) =>
          _selectedClass!.studentIds.contains(s.id)
      ).toList();
    }

    // Sort: Present first, then by name
    filteredStudents.sort((a, b) {
      final aPresent = _presentStudentIds.contains(a.id) ? 0 : 1;
      final bPresent = _presentStudentIds.contains(b.id) ? 0 : 1;
      if (aPresent != bPresent) return aPresent.compareTo(bPresent);
      return a.fullName.compareTo(b.fullName);
    });

    if (filteredStudents.isEmpty) {
      return Center(
        child: Text(
          'Nenhum aluno encontrado',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final student = filteredStudents[index];
        final isPresent = _presentStudentIds.contains(student.id);

        return _AttendanceStudentCard(
          student: student,
          isPresent: isPresent,
          onTap: () => _toggleAttendance(student),
        );
      },
    );
  }
}

/// Attendance Student Card
class _AttendanceStudentCard extends StatelessWidget {
  final Student student;
  final bool isPresent;
  final VoidCallback onTap;

  const _AttendanceStudentCard({
    required this.student,
    required this.isPresent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isPresent ? Colors.green.shade50 : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              _buildAvatar(),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _buildBeltIndicator(),
                        const SizedBox(width: 8),
                        Text(
                          '${student.totalAttendanceCount} presenças',
                          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Check button
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isPresent ? Colors.green : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPresent ? Icons.check : Icons.add,
                  color: isPresent ? Colors.white : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (student.photoUrl != null) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(student.photoUrl!),
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: _getBeltColor(student.currentBelt),
      child: Text(
        student.fullName.substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: student.currentBelt == 'white' ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildBeltIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getBeltColor(student.currentBelt),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getBeltShortLabel(student.currentBelt),
            style: TextStyle(
              fontSize: 10,
              color: student.currentBelt == 'white' ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (student.currentStripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '• ${student.currentStripes}',
              style: TextStyle(
                fontSize: 10,
                color: student.currentBelt == 'white' ? Colors.black : Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFFF5F5F5),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
    };
    return colors[belt] ?? Colors.grey;
  }

  String _getBeltShortLabel(String belt) {
    const labels = {
      'white': 'BR',
      'blue': 'AZ',
      'purple': 'RX',
      'brown': 'MR',
      'black': 'PT',
    };
    return labels[belt] ?? belt.toUpperCase().substring(0, 2);
  }
}
