import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Widget de avatar do aluno tolerante à transição Firestore → Tatami
/// (doc 03 §3).
///
/// Tenta `photoPath` (URL emitida pelo Tatami) primeiro; se ausente, cai
/// para `legacyPhotoUrl` (URL antiga do Firebase Storage que ainda não
/// migrou para GCS). Sem nenhum dos dois → mostra a inicial do nome num
/// circle colorido (default `Colors.grey.shade300`).
///
/// Uso típico:
/// ```dart
/// StudentAvatar(
///   photoPath: apiStudent.photoUrl,        // Tatami response
///   legacyPhotoUrl: legacyStudent.photoUrl, // Firestore mirror
///   displayName: student.fullName,
///   radius: 22,
/// );
/// ```
class StudentAvatar extends StatelessWidget {
  const StudentAvatar({
    super.key,
    this.photoPath,
    this.legacyPhotoUrl,
    required this.displayName,
    this.radius = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String? photoPath;
  final String? legacyPhotoUrl;
  final String displayName;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  String? get _effectiveUrl {
    if (photoPath != null && photoPath!.isNotEmpty) return photoPath;
    if (legacyPhotoUrl != null && legacyPhotoUrl!.isNotEmpty) {
      return legacyPhotoUrl;
    }
    return null;
  }

  String get _initial {
    final t = displayName.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = _effectiveUrl;
    final bg = backgroundColor ?? Colors.grey.shade300;
    final fg = foregroundColor ?? Colors.grey.shade700;

    if (url == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          _initial,
          style: TextStyle(
            color: fg,
            fontSize: radius * 0.9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: bg,
            alignment: Alignment.center,
            child: SizedBox(
              width: radius,
              height: radius,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(fg),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: bg,
            alignment: Alignment.center,
            child: Text(
              _initial,
              style: TextStyle(
                color: fg,
                fontSize: radius * 0.9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
