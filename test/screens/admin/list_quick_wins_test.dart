import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/student.dart';
import 'package:graduabjj/screens/admin/widgets/attendance_student_filter.dart';
import 'package:graduabjj/screens/admin/widgets/student_list_filter.dart';
import 'package:graduabjj/services/belt_progression_service.dart';
import 'package:graduabjj/widgets/common/debounced_search_field.dart';

Student _student({
  required String id,
  required String name,
  StudentStatus status = StudentStatus.active,
  String? nickname,
  String? email,
  String? linkedUserId,
  int attendanceCount = 0,
}) {
  final now = DateTime.utc(2026, 8, 10);
  return Student(
    id: id,
    fullName: name,
    nickname: nickname,
    email: email,
    linkedUserId: linkedUserId,
    startDate: now,
    currentBelt: 'white',
    currentStripes: 0,
    category: StudentCategory.adult,
    status: status,
    tuitionValue: 0,
    tuitionDay: 10,
    attendanceCount: attendanceCount,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('filterStudentsForAdminList', () {
    test('combina busca e status sem exibir transferidos por padrão', () {
      final result = filterStudentsForAdminList(
        students: [
          _student(id: '1', name: 'Ana Silva', email: 'ana@dojo.com'),
          _student(id: '2', name: 'Bruno Souza', nickname: 'Montanha'),
          _student(
            id: '3',
            name: 'Ana Transferida',
            status: StudentStatus.transferred,
          ),
        ],
        searchQuery: 'ana',
        statusFilter: null,
        categoryFilter: null,
        sportFilter: null,
        beltFilter: null,
        accountFilter: null,
        inactivityFilter: null,
        sortBy: 'name',
        eligibilityByStudent: const {},
      );

      expect(result.map((student) => student.id), ['1']);
    });

    test('ordena elegíveis e depois o maior progresso', () {
      final result = filterStudentsForAdminList(
        students: [
          _student(id: '1', name: 'Ana'),
          _student(id: '2', name: 'Bruno'),
          _student(id: '3', name: 'Carla'),
        ],
        searchQuery: '',
        statusFilter: null,
        categoryFilter: null,
        sportFilter: null,
        beltFilter: null,
        accountFilter: null,
        inactivityFilter: null,
        sortBy: 'eligible_first',
        eligibilityByStudent: const {
          '1': EligibilitySnapshotEntry(
            studentId: '1',
            eligible: false,
            currentClasses: 8,
            requiredClasses: 10,
            missingClasses: 2,
            weighted: false,
          ),
          '2': EligibilitySnapshotEntry(
            studentId: '2',
            eligible: true,
            currentClasses: 10,
            requiredClasses: 10,
            missingClasses: 0,
            weighted: false,
          ),
          '3': EligibilitySnapshotEntry(
            studentId: '3',
            eligible: false,
            currentClasses: 5,
            requiredClasses: 10,
            missingClasses: 5,
            weighted: false,
          ),
        },
      );

      expect(result.map((student) => student.id), ['2', '1', '3']);
    });
  });

  test('filtro de chamada não ordena nem modifica a lista original', () {
    final students = [
      _student(id: '1', name: 'Zulu'),
      _student(id: '2', name: 'Ana'),
      _student(id: '3', name: 'Bruno'),
    ];

    final result = filterAttendanceStudents(
      students: students,
      searchQuery: '',
      classStudentIds: {'1', '2'},
      presentStudentIds: {'2'},
      filterMode: 'present',
    );

    expect(result.map((student) => student.id), ['2']);
    expect(students.map((student) => student.id), ['1', '2', '3']);
  });

  // Regressão real (04/set/2026): turma sem roster fixo (studentIds vazio) é
  // a forma hoje de fazer "chamada sem turma" — ex. musculação livre, onde
  // qualquer aluno pode ser marcado presente a qualquer hora do dia. Espelha
  // a mesma regra legada de BJJClass.acceptsCheckinFrom
  // (studentIds.isEmpty || contains(...)): roster vazio = turma ABERTA, deve
  // mostrar TODOS os alunos, não nenhum.
  test('turma com roster vazio (aberta) mostra todos os alunos, não nenhum', () {
    final students = [
      _student(id: '1', name: 'Ana'),
      _student(id: '2', name: 'Bruno'),
    ];

    final result = filterAttendanceStudents(
      students: students,
      searchQuery: '',
      classStudentIds: <String>{},
      presentStudentIds: const {},
      filterMode: 'all',
    );

    expect(result.map((student) => student.id), ['1', '2']);
  });

  testWidgets('busca só notifica após debounce e limpa imediatamente', (
    tester,
  ) async {
    final values = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebouncedSearchField(
            hintText: 'Buscar...',
            onChanged: values.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Ana');
    await tester.pump(const Duration(milliseconds: 200));
    expect(values, isEmpty);

    await tester.pump(const Duration(milliseconds: 60));
    expect(values, ['Ana']);

    await tester.tap(find.byTooltip('Limpar busca'));
    await tester.pump();
    expect(values, ['Ana', '']);
    expect(find.text('Ana'), findsNothing);
  });
}
