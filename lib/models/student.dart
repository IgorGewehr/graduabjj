import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/dto/student_dto.dart' as api;

import '../core/sports.dart';

/// Student Status
enum StudentStatus { active, injured, inactive, suspended }

/// Wrapper que adapta um [api.ApiStudent] para os getters legacy que a
/// factory [Student.fromApiStudent] consome. Convive com Firestore sem
/// importar referências cruzadas e mantém a tradução de enum/null/JSON
/// concentrada em um só lugar.
class _StudentApiLike {
  _StudentApiLike(this._s);
  final api.ApiStudent _s;

  String get id => _s.id;
  String get fullName => _s.fullName;
  String? get nickname => _s.nickname;
  DateTime? get birthDate => _s.birthDate;
  String? get cpf => _s.cpf;
  String? get rg => _s.rg;
  String? get phone => _s.phone;
  String? get email => _s.email;
  String? get photoUrl => _s.photoUrl;
  DateTime? get startDate => _s.startDate;
  DateTime? get jiujitsuStartDate => _s.jiujitsuStartDate;
  String get currentBelt => _s.currentBelt.wire;
  int get currentStripes => _s.currentStripes;
  double? get weightKg => _s.weightKg;
  int get attendanceCount => _s.attendanceCount;
  int? get initialAttendanceCount => _s.initialAttendanceCount;
  String? get statusNote => _s.statusNote;
  String? get tuitionValue => _s.tuitionValue;
  int? get tuitionDay => _s.tuitionDay;
  String? get planId => _s.planId;
  String? get medicalCertificateUrl => _s.medicalCertificateUrl;
  String? get healthNotes => _s.healthNotes;
  String? get bloodType => _s.bloodType;
  String? get allergies => _s.allergies;
  String? get linkedUserUid => _s.linkedUserUid;
  bool get isProfilePublic => _s.isProfilePublic;
  String get primarySport => _s.primarySport;
  List<String> get sportsList => _s.sportsList;
  Map<String, dynamic>? get sportData => _s.sportData;
  DateTime? get createdAt => _s.createdAt;
  DateTime? get updatedAt => _s.updatedAt;

  StudentCategory get categoryLegacy =>
      _s.category == api.ApiStudentCategory.kids
          ? StudentCategory.kids
          : StudentCategory.adult;

  /// Tatami `removed` (soft delete) vira `inactive` no legacy — preserva o
  /// invariante de StudentStatus que NÃO tem `removed`.
  StudentStatus get statusLegacy {
    switch (_s.status) {
      case api.ApiStudentStatus.active:
        return StudentStatus.active;
      case api.ApiStudentStatus.injured:
        return StudentStatus.injured;
      case api.ApiStudentStatus.suspended:
        return StudentStatus.suspended;
      case api.ApiStudentStatus.inactive:
      case api.ApiStudentStatus.removed:
        return StudentStatus.inactive;
    }
  }

  Address? get addressLegacy {
    final a = _s.address;
    if (a == null || a.isEmpty) return null;
    return Address(
      street: a.street ?? '',
      number: '',
      neighborhood: '',
      city: a.city ?? '',
      state: a.state ?? '',
      zipCode: a.zipCode ?? '',
    );
  }

  Guardian? get guardianLegacy {
    final g = _s.guardian;
    if (g == null || g.isEmpty) return null;
    return Guardian(
      name: g.name ?? '',
      phone: g.phone ?? '',
      email: g.email,
      cpf: g.cpf,
      relationship: 'guardian',
    );
  }

  /// Tatami expõe `emergency_contact` como string livre, enquanto o domain
  /// legacy é objeto estruturado. Caller pode lidar com o campo opaco
  /// `_s.emergencyContact` separadamente se precisar.
  EmergencyContact? get emergencyContactLegacy {
    final ec = _s.emergencyContact;
    if (ec == null || ec.isEmpty) return null;
    return EmergencyContact(name: ec, phone: '', relationship: 'emergency');
  }
}

/// Wraps an ApiStudent in the legacy-shaped adapter.
_StudentApiLike _apiLike(api.ApiStudent s) => _StudentApiLike(s);

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
    }
  }

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

  // Belt History
  final List<BeltHistoryEntry>? beltHistory;

  // Attendance
  final int? initialAttendanceCount;
  final int? attendanceCount;

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

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  Student({
    required this.id,
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
    required this.startDate,
    this.jiujitsuStartDate,
    required this.currentBelt,
    required this.currentStripes,
    required this.category,
    this.teamId,
    this.weight,
    this.beltHistory,
    this.initialAttendanceCount,
    this.attendanceCount,
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
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  /// Constrói um [Student] a partir do DTO [api.ApiStudent] (resposta dos
  /// endpoints `/v1/academies/{id}/students*` do Tatami).
  ///
  /// Sprint 2 wiring (FE-only). Esta factory é o ponto de tradução
  /// snake_case → camelCase entre o backend novo e o domain legacy.
  ///
  /// Pontos de atenção:
  /// - `tuitionValue` legacy é `double` não-nulo; Tatami devolve
  ///   `decimal string` opcional. Aqui defaultamos para 0.0.
  /// - `tuitionDay` legacy é `int` não-nulo; defaultamos para 10
  ///   quando ausente (mesmo default do `StudentService.create`).
  /// - `status` legacy NÃO tem `removed`; o Tatami soft-delete vira
  ///   `inactive` para preservar o invariante.
  /// - `beltHistory` NÃO é populado aqui — esse historico vem via
  ///   `student_repo.listBeltProgressions(...)`. Vide doc 10 §"Adapter".
  static Student fromApi(api.ApiStudent s) => _fromApiLike(_apiLike(s));

  static Student _fromApiLike(_StudentApiLike s) {
    return Student(
      id: s.id,
      fullName: s.fullName,
      nickname: s.nickname,
      birthDate: s.birthDate,
      cpf: s.cpf,
      rg: s.rg,
      phone: s.phone,
      email: s.email,
      photoUrl: s.photoUrl,
      address: s.addressLegacy,
      guardian: s.guardianLegacy,
      startDate: s.startDate ?? s.createdAt ?? DateTime.now(),
      jiujitsuStartDate: s.jiujitsuStartDate,
      currentBelt: s.currentBelt,
      currentStripes: s.currentStripes,
      category: s.categoryLegacy,
      weight: s.weightKg,
      initialAttendanceCount: s.initialAttendanceCount,
      attendanceCount: s.attendanceCount,
      status: s.statusLegacy,
      statusNote: s.statusNote,
      planId: s.planId,
      tuitionValue:
          s.tuitionValue == null ? 0.0 : double.tryParse(s.tuitionValue!) ?? 0.0,
      tuitionDay: s.tuitionDay ?? 10,
      medicalCertificateUrl: s.medicalCertificateUrl,
      healthNotes: s.healthNotes,
      bloodType: s.bloodType,
      allergies: s.allergies == null ? null : [s.allergies!],
      emergencyContact: s.emergencyContactLegacy,
      sportsList: s.sportsList.isEmpty ? null : s.sportsList,
      sportData: s.sportData,
      primarySport: s.primarySport,
      isProfilePublic: s.isProfilePublic,
      linkedUserId: s.linkedUserUid,
      createdAt: s.createdAt ?? DateTime.now(),
      updatedAt: s.updatedAt ?? DateTime.now(),
    );
  }

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Student(
      id: doc.id,
      fullName: data['fullName'] ?? '',
      nickname: data['nickname'],
      birthDate: data['birthDate'] != null
          ? (data['birthDate'] as Timestamp).toDate()
          : null,
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
      currentStripes: data['currentStripes'] ?? 0,
      category: StudentCategoryExtension.fromString(data['category'] ?? 'adult'),
      teamId: data['teamId'],
      weight: data['weight']?.toDouble(),
      beltHistory: data['beltHistory'] != null
          ? (data['beltHistory'] as List)
              .map((e) => BeltHistoryEntry.fromMap(e))
              .toList()
          : null,
      initialAttendanceCount: data['initialAttendanceCount'],
      attendanceCount: data['attendanceCount'],
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
      'beltHistory': beltHistory?.map((e) => e.toMap()).toList(),
      'initialAttendanceCount': initialAttendanceCount,
      'attendanceCount': attendanceCount,
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
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'createdBy': createdBy,
    };
  }

  // Computed properties
  String get displayName => nickname ?? fullName.split(' ').first;

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
      currentStripes: data['currentStripes'] as int? ?? 0,
    );
  }

  Student copyWith({
    String? id,
    String? fullName,
    String? nickname,
    DateTime? birthDate,
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
    List<BeltHistoryEntry>? beltHistory,
    int? initialAttendanceCount,
    int? attendanceCount,
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
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return Student(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      nickname: nickname ?? this.nickname,
      birthDate: birthDate ?? this.birthDate,
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
      beltHistory: beltHistory ?? this.beltHistory,
      initialAttendanceCount: initialAttendanceCount ?? this.initialAttendanceCount,
      attendanceCount: attendanceCount ?? this.attendanceCount,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
