import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sports.dart';

/// Student Status
/// `transferred` = aluno que SAIU da academia (foi para outra ou deixou de
/// treinar). É um estado terminal/ex-aluno: some do roster ativo, mas a ficha e
/// todo o histórico (presenças/financeiro) permanecem na academia para consulta.
enum StudentStatus { active, injured, inactive, suspended, transferred }

extension StudentStatusExtension on StudentStatus {
  String get value {
    switch (this) {
      case StudentStatus.active:
        return 'active';
      case StudentStatus.injured:
        return 'injured';
      case StudentStatus.inactive:
        return 'inactive';
      case StudentStatus.suspended:
        return 'suspended';
      case StudentStatus.transferred:
        return 'transferred';
    }
  }

  String get label {
    switch (this) {
      case StudentStatus.active:
        return 'Ativo';
      case StudentStatus.injured:
        return 'Lesionado';
      case StudentStatus.inactive:
        return 'Inativo';
      case StudentStatus.suspended:
        return 'Suspenso';
      case StudentStatus.transferred:
        return 'Transferido';
    }
  }

  /// Ex-aluno: saiu da academia (vai para a aba "Ex-alunos", não no roster ativo).
  bool get isFormer =>
      this == StudentStatus.transferred || this == StudentStatus.inactive;

  static StudentStatus fromString(String value) {
    switch (value) {
      case 'active':
        return StudentStatus.active;
      case 'injured':
        return StudentStatus.injured;
      case 'inactive':
        return StudentStatus.inactive;
      case 'suspended':
        return StudentStatus.suspended;
      case 'transferred':
        return StudentStatus.transferred;
      default:
        return StudentStatus.active;
    }
  }
}

/// Student Category
enum StudentCategory { kids, adult }

extension StudentCategoryExtension on StudentCategory {
  String get value {
    switch (this) {
      case StudentCategory.kids:
        return 'kids';
      case StudentCategory.adult:
        return 'adult';
    }
  }

  String get label {
    switch (this) {
      case StudentCategory.kids:
        return 'Infantil';
      case StudentCategory.adult:
        return 'Adulto';
    }
  }

  static StudentCategory fromString(String value) {
    return value == 'kids' ? StudentCategory.kids : StudentCategory.adult;
  }
}

/// Biological sex — optional, used by body-composition formulas (skinfold %fat
/// via Jackson-Pollock). Nullable everywhere: absent = unknown.
enum Sex { male, female }

extension SexExtension on Sex {
  String get value => this == Sex.male ? 'male' : 'female';
  String get label => this == Sex.male ? 'Masculino' : 'Feminino';

  static Sex? fromString(String? value) {
    switch (value) {
      case 'male':
        return Sex.male;
      case 'female':
        return Sex.female;
      default:
        return null;
    }
  }
}

/// Address Model
class Address {
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String zipCode;

  Address({
    required this.street,
    required this.number,
    this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    required this.zipCode,
  });

  factory Address.fromMap(Map<String, dynamic> map) {
    return Address(
      street: map['street'] ?? '',
      number: map['number'] ?? '',
      complement: map['complement'],
      neighborhood: map['neighborhood'] ?? '',
      city: map['city'] ?? '',
      state: map['state'] ?? '',
      zipCode: map['zipCode'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'street': street,
      'number': number,
      'complement': complement,
      'neighborhood': neighborhood,
      'city': city,
      'state': state,
      'zipCode': zipCode,
    };
  }

  String get fullAddress {
    final parts = [street, number];
    if (complement != null && complement!.isNotEmpty) {
      parts.add(complement!);
    }
    parts.addAll([neighborhood, city, state, zipCode]);
    return parts.join(', ');
  }
}

/// Guardian Model
class Guardian {
  final String name;
  final String phone;
  final String? email;
  final String? cpf;
  final String relationship;

  Guardian({
    required this.name,
    required this.phone,
    this.email,
    this.cpf,
    required this.relationship,
  });

  factory Guardian.fromMap(Map<String, dynamic> map) {
    return Guardian(
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'],
      cpf: map['cpf'],
      relationship: map['relationship'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'cpf': cpf,
      'relationship': relationship,
    };
  }
}

/// Emergency Contact Model
class EmergencyContact {
  final String name;
  final String phone;
  final String relationship;

  EmergencyContact({
    required this.name,
    required this.phone,
    required this.relationship,
  });

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    return EmergencyContact(
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      relationship: map['relationship'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'relationship': relationship,
    };
  }
}

/// Belt History Entry
class BeltHistoryEntry {
  final String belt;
  final int stripes;
  final DateTime date;
  final String? notes;

  BeltHistoryEntry({
    required this.belt,
    required this.stripes,
    required this.date,
    this.notes,
  });

  factory BeltHistoryEntry.fromMap(Map<String, dynamic> map) {
    return BeltHistoryEntry(
      belt: map['belt'] ?? 'white',
      stripes: map['stripes'] ?? 0,
      date: (map['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'belt': belt,
      'stripes': stripes,
      'date': Timestamp.fromDate(date),
      'notes': notes,
    };
  }
}

/// Student Model
class Student {
  final String id;

  // Personal Info
  final String fullName;
  final String? nickname;
  final DateTime? birthDate;
  /// Biological sex (optional) — feeds body-composition formulas.
  final Sex? sex;
  final String? cpf;
  final String? rg;
  final String? phone;
  final String? email;
  final String? photoUrl;

  // Address
  final Address? address;

  // Guardian (for kids)
  final Guardian? guardian;

  // Jiu-Jitsu Info
  final DateTime startDate;
  final DateTime? jiujitsuStartDate;
  final String currentBelt;
  final int currentStripes;
  final StudentCategory category;
  final String? teamId;
  final double? weight;

  // Active body-composition goal (optional) — the student's current target,
  // used by the portal "Minha Evolução" progress bars. Direction (gain/lose)
  // is inferred from the first measurement → target.
  final double? targetWeightKg;
  final double? targetBodyFatPct;

  // Belt History
  final List<BeltHistoryEntry>? beltHistory;

  // Attendance
  final int? initialAttendanceCount;
  final int? attendanceCount;

  /// Per-student monthly attendance goal override (A4). When null/0 the academy
  /// default applies.
  final int? monthlyAttendanceGoal;

  // Status
  final StudentStatus status;
  final String? statusNote;

  // Financial
  final String? planId;
  final double tuitionValue;
  final int tuitionDay;

  // Medical
  final String? medicalCertificateUrl;
  final DateTime? medicalCertificateExpiry;
  final String? healthNotes;
  final String? bloodType;
  final List<String>? allergies;
  final EmergencyContact? emergencyContact;

  // Multi-Sport (optional — backward compat: absent = assume BJJ)
  final List<String>? sportsList;
  final Map<String, dynamic>? sportData;
  final String? primarySport;

  // Privacy & Account Link
  final bool isProfilePublic;
  final String? linkedUserId;

  // Responsible (kids → adult): the adult student/account who pays this kid's
  // charges. Set by an admin. `responsibleUserId` is the adult's auth uid and is
  // the source of truth for the portal, Firestore rules and payment auth; the
  // other two are denormalized for display.
  final String? responsibleUserId;
  final String? responsibleStudentId;
  final String? responsibleName;
  /// Admin-set intent flag: the responsible adult also trains at this academy.
  /// UI gate for the responsible picker; the actual billing/visibility routing
  /// still keys off `responsibleUserId` / `hasResponsible`.
  final bool responsibleTrainsHere;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  Student({
    required this.id,
    required this.fullName,
    this.nickname,
    this.birthDate,
    this.sex,
    this.cpf,
    this.rg,
    this.phone,
    this.email,
    this.photoUrl,
    this.address,
    this.guardian,
    required this.startDate,
    this.jiujitsuStartDate,
    required this.currentBelt,
    required this.currentStripes,
    required this.category,
    this.teamId,
    this.weight,
    this.targetWeightKg,
    this.targetBodyFatPct,
    this.beltHistory,
    this.initialAttendanceCount,
    this.attendanceCount,
    this.monthlyAttendanceGoal,
    required this.status,
    this.statusNote,
    this.planId,
    required this.tuitionValue,
    required this.tuitionDay,
    this.medicalCertificateUrl,
    this.medicalCertificateExpiry,
    this.healthNotes,
    this.bloodType,
    this.allergies,
    this.emergencyContact,
    this.sportsList,
    this.sportData,
    this.primarySport,
    this.isProfilePublic = false,
    this.linkedUserId,
    this.responsibleUserId,
    this.responsibleStudentId,
    this.responsibleName,
    this.responsibleTrainsHere = false,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Student(
      id: doc.id,
      fullName: data['fullName'] ?? '',
      nickname: data['nickname'],
      birthDate: data['birthDate'] != null
          ? (data['birthDate'] as Timestamp).toDate()
          : null,
      sex: SexExtension.fromString(data['sex'] as String?),
      cpf: data['cpf'],
      rg: data['rg'],
      phone: data['phone'],
      email: data['email'],
      photoUrl: data['photoUrl'],
      address:
          data['address'] != null ? Address.fromMap(data['address']) : null,
      guardian:
          data['guardian'] != null ? Guardian.fromMap(data['guardian']) : null,
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      jiujitsuStartDate: data['jiujitsuStartDate'] != null
          ? (data['jiujitsuStartDate'] as Timestamp).toDate()
          : null,
      currentBelt: data['currentBelt'] ?? 'white',
      // num?.toInt(): um doc legado com stripes salvo como double quebrava o
      // parse inteiro do Student (some o aluno da lista).
      currentStripes: (data['currentStripes'] as num?)?.toInt() ?? 0,
      category: StudentCategoryExtension.fromString(data['category'] ?? 'adult'),
      teamId: data['teamId'],
      weight: data['weight']?.toDouble(),
      targetWeightKg: data['targetWeightKg']?.toDouble(),
      targetBodyFatPct: data['targetBodyFatPct']?.toDouble(),
      beltHistory: data['beltHistory'] != null
          ? (data['beltHistory'] as List)
              .map((e) => BeltHistoryEntry.fromMap(e))
              .toList()
          : null,
      initialAttendanceCount: data['initialAttendanceCount'],
      attendanceCount: data['attendanceCount'],
      monthlyAttendanceGoal: (data['monthlyAttendanceGoal'] as num?)?.toInt(),
      status: StudentStatusExtension.fromString(data['status'] ?? 'active'),
      statusNote: data['statusNote'],
      planId: data['planId'],
      tuitionValue: (data['tuitionValue'] ?? 0).toDouble(),
      tuitionDay: data['tuitionDay'] ?? 10,
      medicalCertificateUrl: data['medicalCertificateUrl'],
      medicalCertificateExpiry: data['medicalCertificateExpiry'] != null
          ? (data['medicalCertificateExpiry'] as Timestamp).toDate()
          : null,
      healthNotes: data['healthNotes'],
      bloodType: data['bloodType'],
      allergies:
          data['allergies'] != null ? List<String>.from(data['allergies']) : null,
      emergencyContact: data['emergencyContact'] != null
          ? EmergencyContact.fromMap(data['emergencyContact'])
          : null,
      sportsList: data['sports'] != null ? List<String>.from(data['sports']) : null,
      sportData: data['sportData'] != null
          ? Map<String, dynamic>.from(data['sportData'])
          : null,
      primarySport: data['primarySport'],
      isProfilePublic: data['isProfilePublic'] ?? false,
      linkedUserId: data['linkedUserId'],
      responsibleUserId: data['responsibleUserId'],
      responsibleStudentId: data['responsibleStudentId'],
      responsibleName: data['responsibleName'],
      responsibleTrainsHere: data['responsibleTrainsHere'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fullName': fullName,
      'nickname': nickname,
      'birthDate': birthDate != null ? Timestamp.fromDate(birthDate!) : null,
      'sex': sex?.value,
      'cpf': cpf,
      'rg': rg,
      'phone': phone,
      'email': email,
      'photoUrl': photoUrl,
      'address': address?.toMap(),
      'guardian': guardian?.toMap(),
      'startDate': Timestamp.fromDate(startDate),
      'jiujitsuStartDate':
          jiujitsuStartDate != null ? Timestamp.fromDate(jiujitsuStartDate!) : null,
      'currentBelt': currentBelt,
      'currentStripes': currentStripes,
      'category': category.value,
      'teamId': teamId,
      'weight': weight,
      'targetWeightKg': targetWeightKg,
      'targetBodyFatPct': targetBodyFatPct,
      'beltHistory': beltHistory?.map((e) => e.toMap()).toList(),
      'initialAttendanceCount': initialAttendanceCount,
      'attendanceCount': attendanceCount,
      'monthlyAttendanceGoal': monthlyAttendanceGoal,
      'status': status.value,
      'statusNote': statusNote,
      // planId is no longer written — plans are determined by plan.studentIds
      'tuitionValue': tuitionValue,
      'tuitionDay': tuitionDay,
      'medicalCertificateUrl': medicalCertificateUrl,
      'medicalCertificateExpiry': medicalCertificateExpiry != null
          ? Timestamp.fromDate(medicalCertificateExpiry!)
          : null,
      'healthNotes': healthNotes,
      'bloodType': bloodType,
      'allergies': allergies,
      'emergencyContact': emergencyContact?.toMap(),
      'sports': sportsList,
      'sportData': sportData,
      'primarySport': primarySport,
      'isProfilePublic': isProfilePublic,
      'linkedUserId': linkedUserId,
      'responsibleUserId': responsibleUserId,
      'responsibleStudentId': responsibleStudentId,
      'responsibleName': responsibleName,
      'responsibleTrainsHere': responsibleTrainsHere,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'createdBy': createdBy,
    };
  }

  // Computed properties
  String get displayName {
    // Range-safe: nunca retorna vazio. Os call sites de avatar fazem
    // displayName[0]; um nickname '' (não null) ou fullName vazio causava
    // RangeError e derrubava listas de alunos/chamada inteiras.
    final nick = nickname?.trim() ?? '';
    if (nick.isNotEmpty) return nick;
    final first = fullName.trim().split(' ').first;
    return first.isNotEmpty ? first : 'Aluno';
  }

  int get totalAttendanceCount =>
      (initialAttendanceCount ?? 0) + (attendanceCount ?? 0);

  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    int age = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      age--;
    }
    return age;
  }

  bool get isKids => category == StudentCategory.kids;
  bool get isAdult => category == StudentCategory.adult;
  bool get isActive => status == StudentStatus.active;

  /// True when an adult responsible is set to pay this (kids) student's charges.
  bool get hasResponsible =>
      responsibleUserId != null && responsibleUserId!.isNotEmpty;

  // Guardian convenience getters (for backwards compatibility)
  String? get guardianName => guardian?.name;
  String? get guardianPhone => guardian?.phone;
  String? get guardianEmail => guardian?.email;

  // Medical notes alias (for backwards compatibility)
  String? get medicalNotes => healthNotes;

  // ============================================
  // Multi-Sport Helpers (backward compat)
  // ============================================

  /// Returns the effective list of sports for this student.
  /// If `sports` field is absent, falls back to ['bjj'].
  List<SportId> getSports() {
    if (sportsList != null && sportsList!.isNotEmpty) {
      return sportsList!.map((s) => SportId.fromString(s)).toList();
    }
    return [SportId.bjj];
  }

  /// Returns the primary sport for this student.
  SportId getPrimarySport() {
    if (primarySport != null) return SportId.fromString(primarySport!);
    return getSports().first;
  }

  /// Returns grade info for this student in a given sport.
  /// For BJJ without sportData, falls back to legacy currentBelt/currentStripes.
  ({String currentGrade, int currentStripes})? getGrade(SportId sport) {
    if (sport == SportId.bjj && (sportData == null || sportData!['bjj'] == null)) {
      // Backward compat: use legacy fields
      return (currentGrade: currentBelt, currentStripes: currentStripes);
    }
    final data = sportData?[sport.value];
    if (data == null) return null;
    return (
      currentGrade: data['currentGrade'] as String? ?? 'white',
      currentStripes: (data['currentStripes'] as num?)?.toInt() ?? 0,
    );
  }

  Student copyWith({
    String? id,
    String? fullName,
    String? nickname,
    DateTime? birthDate,
    Sex? sex,
    String? cpf,
    String? rg,
    String? phone,
    String? email,
    String? photoUrl,
    Address? address,
    Guardian? guardian,
    DateTime? startDate,
    DateTime? jiujitsuStartDate,
    String? currentBelt,
    int? currentStripes,
    StudentCategory? category,
    String? teamId,
    double? weight,
    double? targetWeightKg,
    double? targetBodyFatPct,
    List<BeltHistoryEntry>? beltHistory,
    int? initialAttendanceCount,
    int? attendanceCount,
    int? monthlyAttendanceGoal,
    StudentStatus? status,
    String? statusNote,
    String? planId,
    double? tuitionValue,
    int? tuitionDay,
    String? medicalCertificateUrl,
    DateTime? medicalCertificateExpiry,
    String? healthNotes,
    String? bloodType,
    List<String>? allergies,
    EmergencyContact? emergencyContact,
    List<String>? sportsList,
    Map<String, dynamic>? sportData,
    String? primarySport,
    bool? isProfilePublic,
    String? linkedUserId,
    String? responsibleUserId,
    String? responsibleStudentId,
    String? responsibleName,
    bool? responsibleTrainsHere,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return Student(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      nickname: nickname ?? this.nickname,
      birthDate: birthDate ?? this.birthDate,
      sex: sex ?? this.sex,
      cpf: cpf ?? this.cpf,
      rg: rg ?? this.rg,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      address: address ?? this.address,
      guardian: guardian ?? this.guardian,
      startDate: startDate ?? this.startDate,
      jiujitsuStartDate: jiujitsuStartDate ?? this.jiujitsuStartDate,
      currentBelt: currentBelt ?? this.currentBelt,
      currentStripes: currentStripes ?? this.currentStripes,
      category: category ?? this.category,
      teamId: teamId ?? this.teamId,
      weight: weight ?? this.weight,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      targetBodyFatPct: targetBodyFatPct ?? this.targetBodyFatPct,
      beltHistory: beltHistory ?? this.beltHistory,
      initialAttendanceCount: initialAttendanceCount ?? this.initialAttendanceCount,
      attendanceCount: attendanceCount ?? this.attendanceCount,
      monthlyAttendanceGoal:
          monthlyAttendanceGoal ?? this.monthlyAttendanceGoal,
      status: status ?? this.status,
      statusNote: statusNote ?? this.statusNote,
      planId: planId ?? this.planId,
      tuitionValue: tuitionValue ?? this.tuitionValue,
      tuitionDay: tuitionDay ?? this.tuitionDay,
      medicalCertificateUrl: medicalCertificateUrl ?? this.medicalCertificateUrl,
      medicalCertificateExpiry: medicalCertificateExpiry ?? this.medicalCertificateExpiry,
      healthNotes: healthNotes ?? this.healthNotes,
      bloodType: bloodType ?? this.bloodType,
      allergies: allergies ?? this.allergies,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      sportsList: sportsList ?? this.sportsList,
      sportData: sportData ?? this.sportData,
      primarySport: primarySport ?? this.primarySport,
      isProfilePublic: isProfilePublic ?? this.isProfilePublic,
      linkedUserId: linkedUserId ?? this.linkedUserId,
      responsibleUserId: responsibleUserId ?? this.responsibleUserId,
      responsibleStudentId: responsibleStudentId ?? this.responsibleStudentId,
      responsibleName: responsibleName ?? this.responsibleName,
      responsibleTrainsHere:
          responsibleTrainsHere ?? this.responsibleTrainsHere,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
