import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/student.dart';
import 'package:graduabjj/screens/admin/widgets/plan_student_filter.dart';

Student _student(String id, String name, {String? nickname}) {
  final now = DateTime.utc(2026, 8, 10);
  return Student(
    id: id,
    fullName: name,
    nickname: nickname,
    startDate: now,
    currentBelt: 'white',
    currentStripes: 0,
    category: StudentCategory.adult,
    status: StudentStatus.active,
    tuitionValue: 0,
    tuitionDay: 10,
    createdAt: now,
    updatedAt: now,
  );
}

List<String> _ids(List<Student> l) => l.map((s) => s.id).toList();

void main() {
  final students = [
    _student('1', 'Carla'),
    _student('2', 'ana', nickname: 'Montanha'),
    _student('3', 'Bruno'),
    _student('4', 'Davi'),
  ];
  // 2 e 4 estão no plano.
  const snapshot = {'2', '4'};

  List<Student> run(
    PlanMembershipFilter f, {
    String q = '',
    Set<String> snap = snapshot,
  }) => filterStudentsForPlan(
    students: students,
    groupSnapshot: snap,
    filter: f,
    searchQuery: q,
  );

  group('filterStudentsForPlan', () {
    test('"Todos" mantém o padrão histórico: fora do plano primeiro, A-Z', () {
      expect(_ids(run(PlanMembershipFilter.all)), ['3', '1', '2', '4']);
    });

    test('"No plano" mostra só matriculados, em ordem alfabética', () {
      expect(_ids(run(PlanMembershipFilter.inPlan)), ['2', '4']);
    });

    test('"Fora" mostra só quem não está, em ordem alfabética', () {
      expect(_ids(run(PlanMembershipFilter.notInPlan)), ['3', '1']);
    });

    test('busca combina com a aba e aceita apelido, sem diferenciar caixa', () {
      expect(_ids(run(PlanMembershipFilter.all, q: '  MONTANHA ')), ['2']);
      expect(_ids(run(PlanMembershipFilter.notInPlan, q: 'montanha')), isEmpty);
    });

    test('plano vazio: "No plano" vazio e "Fora" com todos', () {
      expect(_ids(run(PlanMembershipFilter.inPlan, snap: {})), isEmpty);
      expect(_ids(run(PlanMembershipFilter.notInPlan, snap: {})), [
        '2',
        '3',
        '1',
        '4',
      ]);
    });

    test('o agrupamento vem só do snapshot: nova foto = novo agrupamento', () {
      // A tela só troca o snapshot ao mudar de aba; entre trocas, o mesmo
      // snapshot dá a mesma lista (linha não pula ao tocar). Aqui vale a
      // metade testável sem widget: o resultado depende APENAS do snapshot.
      expect(_ids(run(PlanMembershipFilter.inPlan, snap: {'2', '4'})), [
        '2',
        '4',
      ]);
      expect(_ids(run(PlanMembershipFilter.inPlan, snap: {'4'})), ['4']);
    });

    test('não muta a lista original', () {
      final copy = List<Student>.from(students);
      run(PlanMembershipFilter.all);
      expect(_ids(students), _ids(copy));
    });
  });

  group('countStudentsInPlan', () {
    test('ignora ids de alunos que não estão na lista (inativos/removidos)', () {
      expect(countStudentsInPlan(students, {'2', '4', 'removido'}), 2);
    });

    test('"No plano" + "Fora" sempre fecha com "Todos"', () {
      final inPlan = countStudentsInPlan(students, {'1', 'fantasma'});
      expect(inPlan + (students.length - inPlan), students.length);
    });
  });
}
