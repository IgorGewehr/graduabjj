import 'package:flutter/foundation.dart';

import '../../models/user.dart';
import '../../services/settings_service.dart';
import 'nav_catalog.dart';

/// Single source linking a [FeatureId] to its boolean value in [AcademySettings].
bool isFeatureEnabled(FeatureId f, AcademySettings? s) {
  switch (f) {
    case FeatureId.store:
      return s?.storeEnabled ?? false;
    case FeatureId.ranking:
      return s?.rankingVisibleToStudents ?? true;
    case FeatureId.journal:
      return s?.journalVisibleToStudents ?? true;
    case FeatureId.graduation:
      return s?.autoGraduationEnabled ?? false;
    case FeatureId.payments:
      return s?.isPaymentEnabled ?? false;
    case FeatureId.musculacao:
      return s?.musculacaoEnabled ?? true;
    case FeatureId.workouts:
      return s?.workoutPlansEnabled ?? true;
    case FeatureId.videos:
      return s?.trainingVideosEnabled ?? true;
    case FeatureId.booking:
      return s?.bookingEnabled ?? false;
  }
}

/// Whether [user] satisfies the permission requirements of [entry].
/// Replicates exactly the current admin gates (incl. absence of admin bypass
/// for financial/reports/graduation/journal).
bool _permissionSatisfied(NavEntry entry, AppUser? user) {
  if (entry.adminOnly && !(user?.isAdmin ?? false)) return false;

  final isAdmin = user?.isAdmin ?? false;

  if (entry.requiresAnyPermission != null) {
    if (entry.adminBypassesPermission && isAdmin) return true;
    return entry.requiresAnyPermission!
        .any((p) => user?.hasPermission(p) ?? false);
  }

  final perm = entry.requiresPermission;
  if (perm != null) {
    if (entry.adminBypassesPermission && isAdmin) return true;
    return user?.hasPermission(perm) ?? false;
  }

  return true;
}

/// Resolves the admin catalog for the current user/settings.
/// Precedence per entry:
///   1) permission/adminOnly not satisfied  -> hidden
///   2) feature == null                     -> visible
///   3) feature ON                          -> visible
///   4) feature OFF && lockable             -> locked
///   5) feature OFF && !lockable            -> hidden
List<ResolvedNavEntry> resolveAdminCatalog({
  required List<NavEntry> catalog,
  required AcademySettings? settings,
  required AppUser? user,
}) {
  return catalog.map((entry) {
    if (!_permissionSatisfied(entry, user)) {
      return ResolvedNavEntry(entry, NavEntryState.hidden);
    }

    final feature = entry.feature;
    if (feature == null || isFeatureEnabled(feature, settings)) {
      return ResolvedNavEntry(entry, NavEntryState.visible);
    }

    // Feature OFF.
    return ResolvedNavEntry(
      entry,
      entry.lockable ? NavEntryState.locked : NavEntryState.hidden,
    );
  }).toList(growable: false);
}

/// Portal context needed for non-AcademySettings gates.
@immutable
class PortalNavContext {
  final bool isKids;
  final bool isMonitorOrAttendance; // isMonitor || hasPermission('attendance:take')
  final bool hasPlan;
  final bool storePublished;
  final bool graduationProgressVisible;

  const PortalNavContext({
    required this.isKids,
    required this.isMonitorOrAttendance,
    required this.hasPlan,
    required this.storePublished,
    required this.graduationProgressVisible,
  });
}

/// Portal: simple gate. Not met => hidden (never locked).
/// Order: feature OFF -> hidden; portalGate not met -> hidden;
///        graduationProgressVisible (special case portal_graduacao) -> hidden;
///        otherwise visible.
List<ResolvedNavEntry> resolvePortalCatalog({
  required List<NavEntry> catalog,
  required AcademySettings? settings,
  required PortalNavContext ctx,
}) {
  return catalog.map((entry) {
    final feature = entry.feature;
    if (feature != null && !isFeatureEnabled(feature, settings)) {
      return ResolvedNavEntry(entry, NavEntryState.hidden);
    }

    switch (entry.portalGate) {
      case PortalContextGate.kidsOnly:
        if (!ctx.isKids) return ResolvedNavEntry(entry, NavEntryState.hidden);
        break;
      case PortalContextGate.hasPlan:
        if (!ctx.hasPlan) return ResolvedNavEntry(entry, NavEntryState.hidden);
        break;
      case PortalContextGate.storePublished:
        if (!ctx.storePublished) {
          return ResolvedNavEntry(entry, NavEntryState.hidden);
        }
        break;
      case PortalContextGate.hideForMonitor:
        if (ctx.isMonitorOrAttendance) {
          return ResolvedNavEntry(entry, NavEntryState.hidden);
        }
        break;
      case null:
        break;
    }

    // Special case (does not use FeatureId): portal_graduacao gates on
    // graduationProgressVisibleToStudents.
    if (entry.key == 'portal_graduacao' && !ctx.graduationProgressVisible) {
      return ResolvedNavEntry(entry, NavEntryState.hidden);
    }

    return ResolvedNavEntry(entry, NavEntryState.visible);
  }).toList(growable: false);
}
