// Providers Riverpod para todos os repositórios remotos do Tatami.
//
// Importe DESTE arquivo nos providers de domínio (auth_provider,
// student_provider, etc.) quando estiver fazendo o wiring de cada sprint.
// Cada repo é stateless e depende do `tatamiClientProvider` único da app.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/api_provider.dart';
import 'attendance_repo.dart';
import 'class_repo.dart';
import 'competition_repo.dart';
import 'financial_repo.dart';
import 'identity_repo.dart';
import 'link_code_repo.dart';
import 'notification_repo.dart';
import 'plan_repo.dart';
import 'settings_repo.dart';
import 'store_repo.dart';
import 'student_repo.dart';
import 'wallet_repo.dart';

// Identity (/v1/me, /v1/users, /v1/academies/{id}/memberships)
final identityRepoProvider = Provider<IdentityRemoteRepo>(
  (ref) => IdentityRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Student (/v1/academies/{id}/students*)
final studentRepoProvider = Provider<StudentRemoteRepo>(
  (ref) => StudentRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Plan (/v1/academies/{id}/plans*)
final planRepoProvider = Provider<PlanRemoteRepo>(
  (ref) => PlanRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Class (/v1/academies/{id}/classes* + roster)
final classRepoProvider = Provider<ClassRemoteRepo>(
  (ref) => ClassRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Settings (/v1/academies/{id}/settings*)
final settingsRepoProvider = Provider<SettingsRemoteRepo>(
  (ref) => SettingsRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Link codes (/v1/academies/{id}/link-codes + /v1/link-codes/{code}/redeem)
final linkCodeRepoProvider = Provider<LinkCodeRemoteRepo>(
  (ref) => LinkCodeRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Financial (/v1/academies/{id}/financials* + payments + monthly + billing)
final financialRepoProvider = Provider<FinancialRemoteRepo>(
  (ref) => FinancialRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Wallet (/v1/academies/{id}/wallet*)
final walletRepoProvider = Provider<WalletRemoteRepo>(
  (ref) => WalletRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Attendance (/v1/academies/{id}/attendance* + QR tokens)
final attendanceRepoProvider = Provider<AttendanceRemoteRepo>(
  (ref) => AttendanceRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Notification (inbox + FCM + broadcast — escopo /me + /academies/{id})
final notificationRepoProvider = Provider<NotificationRemoteRepo>(
  (ref) => NotificationRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Store (/v1/academies/{id}/store/products + orders)
final storeRepoProvider = Provider<StoreRemoteRepo>(
  (ref) => StoreRemoteRepo(ref.watch(tatamiClientProvider)),
);

// Competition (/v1/academies/{id}/competitions* + photos + achievements)
final competitionRepoProvider = Provider<CompetitionRemoteRepo>(
  (ref) => CompetitionRemoteRepo(ref.watch(tatamiClientProvider)),
);
