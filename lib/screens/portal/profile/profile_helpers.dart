import '../../../models/student.dart';

/// Pure utility functions for the Profile screen.
/// All functions are stateless and have no side effects.
abstract final class ProfileHelpers {
  static String formatTrainingTime(DateTime startDate) {
    final now = DateTime.now();
    final difference = now.difference(startDate);
    final months = difference.inDays ~/ 30;

    if (months >= 12) {
      final years = months ~/ 12;
      final remainingMonths = months % 12;
      if (remainingMonths > 0) {
        return '${years}a ${remainingMonths}m';
      }
      return '$years ano${years > 1 ? 's' : ''}';
    } else if (months > 0) {
      return '$months mes${months > 1 ? 'es' : ''}';
    } else {
      final days = difference.inDays;
      return '$days dia${days != 1 ? 's' : ''}';
    }
  }

  static String getPersonalDataSummary(Student student) {
    final parts = <String>[];
    if (student.phone != null && student.phone!.isNotEmpty)
      parts.add(student.phone!);
    if (student.email != null && student.email!.isNotEmpty)
      parts.add(student.email!);
    if (student.nickname != null && student.nickname!.isNotEmpty)
      parts.add(student.nickname!);
    if (parts.isEmpty) return 'Nenhum dado';
    return parts.join(', ');
  }

  static String getAddressSummary(Student student) {
    if (student.address == null || !hasAddress(student.address!)) {
      return 'Nenhum endereco cadastrado';
    }
    final city = student.address!.city;
    final state = student.address!.state;
    if (city.isNotEmpty && state.isNotEmpty) {
      return '$city - $state';
    }
    if (city.isNotEmpty) return city;
    return student.address!.street;
  }

  static String getHealthEmergencySummary(Student student) {
    final parts = <String>[];
    if (student.bloodType != null && student.bloodType!.isNotEmpty) {
      parts.add('Tipo ${student.bloodType}');
    }
    if (student.emergencyContact != null &&
        student.emergencyContact!.name.isNotEmpty) {
      parts.add(student.emergencyContact!.name);
    }
    if (parts.isEmpty) return 'Nenhum dado';
    return parts.join(', ');
  }

  static bool isPersonalDataEmpty(Student student) {
    return (student.nickname == null || student.nickname!.isEmpty) &&
        student.birthDate == null &&
        (student.phone == null || student.phone!.isEmpty) &&
        (student.email == null || student.email!.isEmpty) &&
        (student.cpf == null || student.cpf!.isEmpty) &&
        (student.rg == null || student.rg!.isEmpty) &&
        student.weight == null;
  }

  static bool isHealthDataEmpty(Student student) {
    return (student.bloodType == null || student.bloodType!.isEmpty) &&
        (student.allergies == null || student.allergies!.isEmpty) &&
        (student.healthNotes == null || student.healthNotes!.isEmpty);
  }

  static bool hasAddress(Address address) {
    return address.street.isNotEmpty || address.city.isNotEmpty;
  }
}
