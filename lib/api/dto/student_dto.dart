// DTOs do contexto Student, alinhados 1:1 com api/openapi/student.yaml.
//
// Mesmo padrão de identity_dto.dart: parser puro snake_case→Dart, sem
// Firestore. Enums com fromWire() defensivo (valores desconhecidos
// degradam para um default seguro).

// Enums abaixo casam 1:1 com o wire format do OpenAPI (snake_case). Lint do
// Dart prefere lowerCamelCase, mas isso ia obrigar a manter uma tabela de
// tradução — não vale a complexidade.
// ignore_for_file: constant_identifier_names

enum ApiBelt {
  white,
  blue,
  purple,
  brown,
  black,
  kids_grey,
  kids_yellow,
  kids_orange,
  kids_green,
}

extension ApiBeltX on ApiBelt {
  String get wire => name;
  static ApiBelt fromWire(String? value) {
    if (value == null) return ApiBelt.white;
    for (final b in ApiBelt.values) {
      if (b.name == value) return b;
    }
    return ApiBelt.white;
  }
}

enum ApiStudentStatus { active, injured, inactive, suspended, removed }

extension ApiStudentStatusX on ApiStudentStatus {
  String get wire => name;
  static ApiStudentStatus fromWire(String? value) {
    if (value == null) return ApiStudentStatus.active;
    for (final s in ApiStudentStatus.values) {
      if (s.name == value) return s;
    }
    return ApiStudentStatus.active;
  }
}

enum ApiStudentCategory { kids, adult }

extension ApiStudentCategoryX on ApiStudentCategory {
  String get wire => name;
  static ApiStudentCategory fromWire(String? value) {
    if (value == 'kids') return ApiStudentCategory.kids;
    return ApiStudentCategory.adult;
  }
}

enum ApiSport { bjj, judo, muaythai, wrestling, mma }

extension ApiSportX on ApiSport {
  String get wire => name;
  static ApiSport fromWire(String? value) {
    if (value == null) return ApiSport.bjj;
    for (final s in ApiSport.values) {
      if (s.name == value) return s;
    }
    return ApiSport.bjj;
  }
}

class ApiAddress {
  const ApiAddress({this.street, this.city, this.state, this.zipCode});

  final String? street;
  final String? city;
  final String? state;
  final String? zipCode;

  factory ApiAddress.fromJson(Map<String, dynamic> j) => ApiAddress(
        street: j['street'] as String?,
        city: j['city'] as String?,
        state: j['state'] as String?,
        zipCode: j['zip_code'] as String?,
      );

  bool get isEmpty =>
      street == null && city == null && state == null && zipCode == null;
}

class ApiGuardian {
  const ApiGuardian({this.name, this.cpf, this.phone, this.email});

  final String? name;
  final String? cpf;
  final String? phone;
  final String? email;

  factory ApiGuardian.fromJson(Map<String, dynamic> j) => ApiGuardian(
        name: j['name'] as String?,
        cpf: j['cpf'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
      );

  bool get isEmpty =>
      name == null && cpf == null && phone == null && email == null;
}

class ApiStudent {
  const ApiStudent({
    required this.id,
    required this.academyId,
    required this.fullName,
    required this.currentBelt,
    required this.currentStripes,
    required this.category,
    required this.status,
    required this.attendanceCount,
    required this.isProfilePublic,
    required this.primarySport,
    required this.sportsList,
    this.nickname,
    this.birthDate,
    this.cpf,
    this.rg,
    this.phone,
    this.email,
    this.photoUrl,
    this.address,
    this.guardian,
    this.startDate,
    this.jiujitsuStartDate,
    this.weightKg,
    this.initialAttendanceCount,
    this.statusNote,
    this.tuitionValue,
    this.tuitionDay,
    this.planId,
    this.medicalCertificateUrl,
    this.healthNotes,
    this.bloodType,
    this.allergies,
    this.emergencyContact,
    this.linkedUserUid,
    this.sportData,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String academyId;
  final String fullName;
  final String? nickname;
  final DateTime? birthDate;
  final String? cpf;
  final String? rg;
  final String? phone;
  final String? email;
  final String? photoUrl;
  final ApiAddress? address;
  final ApiGuardian? guardian;
  final DateTime? startDate;
  final DateTime? jiujitsuStartDate;
  final ApiBelt currentBelt;
  final int currentStripes;
  final ApiStudentCategory category;
  final double? weightKg;
  final int attendanceCount;
  final int? initialAttendanceCount;
  final ApiStudentStatus status;
  final String? statusNote;
  final String? tuitionValue;
  final int? tuitionDay;
  final String? planId;
  final String? medicalCertificateUrl;
  final String? healthNotes;
  final String? bloodType;
  final String? allergies;
  final String? emergencyContact;
  final String? linkedUserUid;
  final bool isProfilePublic;
  final String primarySport;
  final List<String> sportsList;
  final Map<String, dynamic>? sportData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == ApiStudentStatus.active;
  bool get isKids => category == ApiStudentCategory.kids;

  factory ApiStudent.fromJson(Map<String, dynamic> j) {
    final addr = j['address'];
    final guardian = j['guardian'];
    return ApiStudent(
      id: j['id'] as String,
      academyId: j['academy_id'] as String,
      fullName: j['full_name'] as String,
      nickname: j['nickname'] as String?,
      birthDate: _parseDate(j['birth_date']),
      cpf: j['cpf'] as String?,
      rg: j['rg'] as String?,
      phone: j['phone'] as String?,
      email: j['email'] as String?,
      photoUrl: j['photo_url'] as String?,
      address: addr is Map<String, dynamic> ? ApiAddress.fromJson(addr) : null,
      guardian:
          guardian is Map<String, dynamic> ? ApiGuardian.fromJson(guardian) : null,
      startDate: _parseDate(j['start_date']),
      jiujitsuStartDate: _parseDate(j['jiujitsu_start_date']),
      currentBelt: ApiBeltX.fromWire(j['current_belt'] as String?),
      currentStripes: (j['current_stripes'] as num?)?.toInt() ?? 0,
      category: ApiStudentCategoryX.fromWire(j['category'] as String?),
      weightKg: (j['weight_kg'] as num?)?.toDouble(),
      attendanceCount: (j['attendance_count'] as num?)?.toInt() ?? 0,
      initialAttendanceCount: (j['initial_attendance_count'] as num?)?.toInt(),
      status: ApiStudentStatusX.fromWire(j['status'] as String?),
      statusNote: j['status_note'] as String?,
      tuitionValue: j['tuition_value'] as String?,
      tuitionDay: (j['tuition_day'] as num?)?.toInt(),
      planId: j['plan_id'] as String?,
      medicalCertificateUrl: j['medical_certificate_url'] as String?,
      healthNotes: j['health_notes'] as String?,
      bloodType: j['blood_type'] as String?,
      allergies: j['allergies'] as String?,
      emergencyContact: j['emergency_contact'] as String?,
      linkedUserUid: j['linked_user_uid'] as String?,
      isProfilePublic: j['is_profile_public'] as bool? ?? false,
      primarySport: j['primary_sport'] as String? ?? 'bjj',
      sportsList: (j['sports_list'] as List?)?.whereType<String>().toList() ??
          const [],
      sportData: j['sport_data'] is Map<String, dynamic>
          ? j['sport_data'] as Map<String, dynamic>
          : null,
      createdAt: _parseDate(j['created_at']),
      updatedAt: _parseDate(j['updated_at']),
    );
  }
}

class StudentsPage {
  const StudentsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiStudent> items;
  final String? nextCursor;
  final bool hasMore;

  factory StudentsPage.fromJson(Map<String, dynamic> j) => StudentsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiStudent.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ApiBeltProgression {
  const ApiBeltProgression({
    required this.id,
    required this.studentId,
    required this.sport,
    required this.previousBelt,
    required this.previousStripes,
    required this.newBelt,
    required this.newStripes,
    required this.promotionDate,
    required this.totalClasses,
    required this.effectiveCountAtPromotion,
    required this.promotedByUid,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String studentId;
  final ApiSport sport;
  final ApiBelt previousBelt;
  final int previousStripes;
  final ApiBelt newBelt;
  final int newStripes;
  final DateTime promotionDate;
  final int totalClasses;
  final int effectiveCountAtPromotion;
  final String promotedByUid;
  final String? notes;
  final DateTime? createdAt;

  factory ApiBeltProgression.fromJson(Map<String, dynamic> j) =>
      ApiBeltProgression(
        id: j['id'] as String,
        studentId: j['student_id'] as String,
        sport: ApiSportX.fromWire(j['sport'] as String?),
        previousBelt: ApiBeltX.fromWire(j['previous_belt'] as String?),
        previousStripes: (j['previous_stripes'] as num?)?.toInt() ?? 0,
        newBelt: ApiBeltX.fromWire(j['new_belt'] as String?),
        newStripes: (j['new_stripes'] as num?)?.toInt() ?? 0,
        promotionDate: _parseDate(j['promotion_date']) ?? DateTime.now(),
        totalClasses: (j['total_classes'] as num?)?.toInt() ?? 0,
        effectiveCountAtPromotion:
            (j['effective_count_at_promotion'] as num?)?.toInt() ?? 0,
        promotedByUid: j['promoted_by_uid'] as String? ?? '',
        notes: j['notes'] as String?,
        createdAt: _parseDate(j['created_at']),
      );
}

class BeltProgressionsPage {
  const BeltProgressionsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiBeltProgression> items;
  final String? nextCursor;
  final bool hasMore;

  factory BeltProgressionsPage.fromJson(Map<String, dynamic> j) =>
      BeltProgressionsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiBeltProgression.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ApiAssessmentScores {
  const ApiAssessmentScores({
    required this.respeito,
    required this.disciplina,
    required this.pontualidade,
    required this.tecnica,
    required this.esforco,
  });

  final int respeito;
  final int disciplina;
  final int pontualidade;
  final int tecnica;
  final int esforco;

  /// Média 1.0–5.0 dos 5 critérios.
  double get average =>
      (respeito + disciplina + pontualidade + tecnica + esforco) / 5.0;

  factory ApiAssessmentScores.fromJson(Map<String, dynamic> j) =>
      ApiAssessmentScores(
        respeito: (j['respeito'] as num?)?.toInt() ?? 0,
        disciplina: (j['disciplina'] as num?)?.toInt() ?? 0,
        pontualidade: (j['pontualidade'] as num?)?.toInt() ?? 0,
        tecnica: (j['tecnica'] as num?)?.toInt() ?? 0,
        esforco: (j['esforco'] as num?)?.toInt() ?? 0,
      );
}

class ApiAssessment {
  const ApiAssessment({
    required this.id,
    required this.studentId,
    required this.date,
    required this.evaluatedByUid,
    required this.scores,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String studentId;
  final DateTime date;
  final String evaluatedByUid;
  final ApiAssessmentScores scores;
  final String? notes;
  final DateTime? createdAt;

  factory ApiAssessment.fromJson(Map<String, dynamic> j) => ApiAssessment(
        id: j['id'] as String,
        studentId: j['student_id'] as String,
        date: _parseDate(j['date']) ?? DateTime.now(),
        evaluatedByUid: j['evaluated_by_uid'] as String,
        scores:
            ApiAssessmentScores.fromJson(j['scores'] as Map<String, dynamic>),
        notes: j['notes'] as String?,
        createdAt: _parseDate(j['created_at']),
      );
}

class AssessmentsPage {
  const AssessmentsPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ApiAssessment> items;
  final String? nextCursor;
  final bool hasMore;

  factory AssessmentsPage.fromJson(Map<String, dynamic> j) => AssessmentsPage(
        items: (j['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApiAssessment.fromJson)
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ApiEligibilityView {
  const ApiEligibilityView({
    required this.eligible,
    required this.currentBelt,
    required this.currentStripes,
    required this.currentCount,
    required this.requiredCount,
    required this.autoEnabled,
    this.reason,
    this.nextBelt,
    this.nextStripes,
    this.lastPromotionDate,
  });

  final bool eligible;
  final String? reason;
  final ApiBelt currentBelt;
  final int currentStripes;
  final ApiBelt? nextBelt;
  final int? nextStripes;

  /// Presenças contadas desde a última promoção (ou início no BJJ se
  /// nunca promovido). Wire field: `current_count`.
  final int currentCount;

  /// Threshold da academia (`auto_graduation_attendances`); default 40
  /// quando não setado. Wire field: `required_count`.
  final int requiredCount;
  final bool autoEnabled;
  final DateTime? lastPromotionDate;

  /// Quantas presenças ainda faltam para ficar elegível.
  /// Zero ou negativo significa que já passou do threshold.
  int get attendancesNeeded =>
      (requiredCount - currentCount).clamp(0, requiredCount);

  factory ApiEligibilityView.fromJson(Map<String, dynamic> j) =>
      ApiEligibilityView(
        eligible: j['eligible'] as bool? ?? false,
        reason: j['reason'] as String?,
        currentBelt: ApiBeltX.fromWire(j['current_belt'] as String?),
        currentStripes: (j['current_stripes'] as num?)?.toInt() ?? 0,
        nextBelt: j['next_belt'] == null
            ? null
            : ApiBeltX.fromWire(j['next_belt'] as String?),
        nextStripes: (j['next_stripes'] as num?)?.toInt(),
        currentCount: (j['current_count'] as num?)?.toInt() ?? 0,
        requiredCount: (j['required_count'] as num?)?.toInt() ?? 40,
        autoEnabled: j['auto_enabled'] as bool? ?? false,
        lastPromotionDate: _parseDate(j['last_promotion_date']),
      );
}

class ApiStudentStats {
  const ApiStudentStats({
    required this.total,
    required this.byStatus,
    required this.byCategory,
    required this.byBelt,
  });

  final int total;
  final Map<ApiStudentStatus, int> byStatus;
  final Map<ApiStudentCategory, int> byCategory;
  final List<StudentBeltCount> byBelt;

  int get activeCount => byStatus[ApiStudentStatus.active] ?? 0;
  int get adultsCount => byCategory[ApiStudentCategory.adult] ?? 0;
  int get kidsCount => byCategory[ApiStudentCategory.kids] ?? 0;

  factory ApiStudentStats.fromJson(Map<String, dynamic> j) {
    final byStatusRaw = _asStringMap(j['by_status']);
    final byCatRaw = _asStringMap(j['by_category']);
    return ApiStudentStats(
      total: (j['total'] as num?)?.toInt() ?? 0,
      byStatus: {
        for (final entry in byStatusRaw.entries)
          ApiStudentStatusX.fromWire(entry.key):
              (entry.value as num?)?.toInt() ?? 0,
      },
      byCategory: {
        // Backend usa 'adults' (plural) e 'kids'; mapeamos para o enum singular.
        if (byCatRaw.containsKey('adults'))
          ApiStudentCategory.adult: (byCatRaw['adults'] as num?)?.toInt() ?? 0,
        if (byCatRaw.containsKey('kids'))
          ApiStudentCategory.kids: (byCatRaw['kids'] as num?)?.toInt() ?? 0,
      },
      byBelt: (j['by_belt'] as List? ?? const [])
          .map((e) => StudentBeltCount.fromJson(_asStringMap(e)))
          .toList(),
    );
  }
}

class StudentBeltCount {
  const StudentBeltCount({
    required this.belt,
    required this.category,
    required this.total,
  });

  final ApiBelt belt;
  final ApiStudentCategory category;
  final int total;

  factory StudentBeltCount.fromJson(Map<String, dynamic> j) => StudentBeltCount(
        belt: ApiBeltX.fromWire(j['belt'] as String?),
        category: ApiStudentCategoryX.fromWire(j['category'] as String?),
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

class CreateStudentRequest {
  const CreateStudentRequest({
    required this.fullName,
    this.nickname,
    this.birthDate,
    this.cpf,
    this.rg,
    this.phone,
    this.email,
    this.photoUrl,
    this.address,
    this.guardian,
    this.startDate,
    this.jiujitsuStartDate,
    this.currentBelt,
    this.currentStripes,
    this.category,
    this.weightKg,
    this.initialAttendanceCount,
    this.tuitionValue,
    this.tuitionDay,
    this.planId,
    this.medicalCertificateUrl,
    this.healthNotes,
    this.bloodType,
    this.allergies,
    this.emergencyContact,
    this.isProfilePublic,
    this.primarySport,
    this.sportsList,
    this.sportData,
  });

  final String fullName;
  final String? nickname;
  final DateTime? birthDate;
  final String? cpf;
  final String? rg;
  final String? phone;
  final String? email;
  final String? photoUrl;
  final ApiAddress? address;
  final ApiGuardian? guardian;
  final DateTime? startDate;
  final DateTime? jiujitsuStartDate;
  final ApiBelt? currentBelt;
  final int? currentStripes;
  final ApiStudentCategory? category;
  final double? weightKg;
  final int? initialAttendanceCount;
  final String? tuitionValue;
  final int? tuitionDay;
  final String? planId;
  final String? medicalCertificateUrl;
  final String? healthNotes;
  final String? bloodType;
  final String? allergies;
  final String? emergencyContact;
  final bool? isProfilePublic;
  final String? primarySport;
  final List<String>? sportsList;
  final Map<String, dynamic>? sportData;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'full_name': fullName};
    if (nickname != null) m['nickname'] = nickname;
    if (birthDate != null) m['birth_date'] = _formatDate(birthDate!);
    if (cpf != null) m['cpf'] = cpf;
    if (rg != null) m['rg'] = rg;
    if (phone != null) m['phone'] = phone;
    if (email != null) m['email'] = email;
    if (photoUrl != null) m['photo_url'] = photoUrl;
    if (address != null) m['address'] = _addressToJson(address!);
    if (guardian != null) m['guardian'] = _guardianToJson(guardian!);
    if (startDate != null) m['start_date'] = _formatDate(startDate!);
    if (jiujitsuStartDate != null) {
      m['jiujitsu_start_date'] = _formatDate(jiujitsuStartDate!);
    }
    if (currentBelt != null) m['current_belt'] = currentBelt!.wire;
    if (currentStripes != null) m['current_stripes'] = currentStripes;
    if (category != null) m['category'] = category!.wire;
    if (weightKg != null) m['weight_kg'] = weightKg;
    if (initialAttendanceCount != null) {
      m['initial_attendance_count'] = initialAttendanceCount;
    }
    if (tuitionValue != null) m['tuition_value'] = tuitionValue;
    if (tuitionDay != null) m['tuition_day'] = tuitionDay;
    if (planId != null) m['plan_id'] = planId;
    if (medicalCertificateUrl != null) {
      m['medical_certificate_url'] = medicalCertificateUrl;
    }
    if (healthNotes != null) m['health_notes'] = healthNotes;
    if (bloodType != null) m['blood_type'] = bloodType;
    if (allergies != null) m['allergies'] = allergies;
    if (emergencyContact != null) m['emergency_contact'] = emergencyContact;
    if (isProfilePublic != null) m['is_profile_public'] = isProfilePublic;
    if (primarySport != null) m['primary_sport'] = primarySport;
    if (sportsList != null) m['sports_list'] = sportsList;
    if (sportData != null) m['sport_data'] = sportData;
    return m;
  }
}

class UpdateStudentRequest {
  const UpdateStudentRequest({
    this.fullName,
    this.nickname,
    this.birthDate,
    this.cpf,
    this.rg,
    this.phone,
    this.email,
    this.photoUrl,
    this.address,
    this.guardian,
    this.startDate,
    this.jiujitsuStartDate,
    this.category,
    this.weightKg,
    this.status,
    this.statusNote,
    this.tuitionValue,
    this.tuitionDay,
    this.planId,
    this.medicalCertificateUrl,
    this.healthNotes,
    this.bloodType,
    this.allergies,
    this.emergencyContact,
    this.isProfilePublic,
    this.primarySport,
  });

  final String? fullName;
  final String? nickname;
  final DateTime? birthDate;
  final String? cpf;
  final String? rg;
  final String? phone;
  final String? email;
  final String? photoUrl;
  final ApiAddress? address;
  final ApiGuardian? guardian;
  final DateTime? startDate;
  final DateTime? jiujitsuStartDate;
  final ApiStudentCategory? category;
  final double? weightKg;
  final ApiStudentStatus? status;
  final String? statusNote;
  final String? tuitionValue;
  final int? tuitionDay;
  final String? planId;
  final String? medicalCertificateUrl;
  final String? healthNotes;
  final String? bloodType;
  final String? allergies;
  final String? emergencyContact;
  final bool? isProfilePublic;
  final String? primarySport;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (fullName != null) m['full_name'] = fullName;
    if (nickname != null) m['nickname'] = nickname;
    if (birthDate != null) m['birth_date'] = _formatDate(birthDate!);
    if (cpf != null) m['cpf'] = cpf;
    if (rg != null) m['rg'] = rg;
    if (phone != null) m['phone'] = phone;
    if (email != null) m['email'] = email;
    if (photoUrl != null) m['photo_url'] = photoUrl;
    if (address != null) m['address'] = _addressToJson(address!);
    if (guardian != null) m['guardian'] = _guardianToJson(guardian!);
    if (startDate != null) m['start_date'] = _formatDate(startDate!);
    if (jiujitsuStartDate != null) {
      m['jiujitsu_start_date'] = _formatDate(jiujitsuStartDate!);
    }
    if (category != null) m['category'] = category!.wire;
    if (weightKg != null) m['weight_kg'] = weightKg;
    if (status != null) m['status'] = status!.wire;
    if (statusNote != null) m['status_note'] = statusNote;
    if (tuitionValue != null) m['tuition_value'] = tuitionValue;
    if (tuitionDay != null) m['tuition_day'] = tuitionDay;
    if (planId != null) m['plan_id'] = planId;
    if (medicalCertificateUrl != null) {
      m['medical_certificate_url'] = medicalCertificateUrl;
    }
    if (healthNotes != null) m['health_notes'] = healthNotes;
    if (bloodType != null) m['blood_type'] = bloodType;
    if (allergies != null) m['allergies'] = allergies;
    if (emergencyContact != null) m['emergency_contact'] = emergencyContact;
    if (isProfilePublic != null) m['is_profile_public'] = isProfilePublic;
    if (primarySport != null) m['primary_sport'] = primarySport;
    return m;
  }
}

class CreateBeltProgressionRequest {
  const CreateBeltProgressionRequest({
    required this.newBelt,
    required this.newStripes,
    required this.promotionDate,
    this.notes,
    this.sport,
  });

  final ApiBelt newBelt;
  final int newStripes;
  final DateTime promotionDate;
  final String? notes;
  final ApiSport? sport;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'new_belt': newBelt.wire,
      'new_stripes': newStripes,
      'promotion_date': _formatDate(promotionDate),
    };
    if (notes != null) m['notes'] = notes;
    if (sport != null) m['sport'] = sport!.wire;
    return m;
  }
}

class CreateAssessmentRequest {
  const CreateAssessmentRequest({
    required this.date,
    required this.scores,
    this.notes,
  });

  final DateTime date;
  final ApiAssessmentScores scores;
  final String? notes;

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'date': _formatDate(date),
      'scores': {
        'respeito': scores.respeito,
        'disciplina': scores.disciplina,
        'pontualidade': scores.pontualidade,
        'tecnica': scores.tecnica,
        'esforco': scores.esforco,
      },
    };
    if (notes != null) m['notes'] = notes;
    return m;
  }
}

class StudentFilter {
  const StudentFilter({
    this.status,
    this.belt,
    this.category,
    this.q,
    this.sport,
    this.limit = 50,
    this.cursor,
  });

  final ApiStudentStatus? status;
  final ApiBelt? belt;
  final ApiStudentCategory? category;
  final String? q;
  final String? sport;
  final int limit;
  final String? cursor;

  Map<String, dynamic> toQueryParameters() {
    final m = <String, dynamic>{'limit': limit};
    if (status != null) m['status'] = status!.wire;
    if (belt != null) m['belt'] = belt!.wire;
    if (category != null) m['category'] = category!.wire;
    if (q != null && q!.isNotEmpty) m['q'] = q;
    if (sport != null) m['sport'] = sport;
    if (cursor != null) m['cursor'] = cursor;
    return m;
  }
}

String _formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, dynamic> _addressToJson(ApiAddress a) {
  final m = <String, dynamic>{};
  if (a.street != null) m['street'] = a.street;
  if (a.city != null) m['city'] = a.city;
  if (a.state != null) m['state'] = a.state;
  if (a.zipCode != null) m['zip_code'] = a.zipCode;
  return m;
}

Map<String, dynamic> _guardianToJson(ApiGuardian g) {
  final m = <String, dynamic>{};
  if (g.name != null) m['name'] = g.name;
  if (g.cpf != null) m['cpf'] = g.cpf;
  if (g.phone != null) m['phone'] = g.phone;
  if (g.email != null) m['email'] = g.email;
  return m;
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Coerção defensiva: aceita `Map<String, dynamic>` vindo de jsonDecode,
/// `Map<dynamic, dynamic>` de literais Dart em testes, ou null.
Map<String, dynamic> _asStringMap(dynamic v) {
  if (v == null) return const <String, dynamic>{};
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return const <String, dynamic>{};
}
