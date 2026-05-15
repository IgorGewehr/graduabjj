import 'package:flutter/material.dart';
import 'package:graduabjj/models/competition_photo.dart';
import 'package:graduabjj/widgets/cached_image.dart';
import 'package:intl/intl.dart';

class PhotoCard extends StatelessWidget {
  final CompetitionPhoto photo;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleHighlight;
  final bool canEdit;
  final bool canDelete;
  final bool canHighlight;

  const PhotoCard({
    super.key,
    required this.photo,
    this.onTap,
    this.onDelete,
    this.onEdit,
    this.onToggleHighlight,
    this.canEdit = false,
    this.canDelete = false,
    this.canHighlight = false,
  });

  Color _getMedalColor() {
    switch (photo.medalType) {
      case CompetitionPosition.gold:
        return const Color(0xFFFFD700);
      case CompetitionPosition.silver:
        return const Color(0xFFC0C0C0);
      case CompetitionPosition.bronze:
        return const Color(0xFFCD7F32);
      default:
        return Colors.grey;
    }
  }

  String _getMedalLabel() {
    return photo.medalType?.label ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final hasActions = canEdit || canDelete || canHighlight;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo with badges
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: AppCachedImage(
                    imageUrl: photo.url,
                    fit: BoxFit.cover,
                    errorIcon: Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, size: 48),
                    ),
                  ),
                ),

                // Medal badge
                if (photo.medalType != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Chip(
                      avatar: const Icon(
                        Icons.emoji_events,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        _getMedalLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: _getMedalColor(),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),

                // Highlight star
                if (photo.isHighlight)
                  const Positioned(
                    top: 8,
                    right: 48,
                    child: Icon(Icons.star, color: Color(0xFFFFD700), size: 28),
                  ),

                // Actions menu
                if (hasActions)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.more_vert, size: 20),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit?.call();
                            break;
                          case 'delete':
                            onDelete?.call();
                            break;
                          case 'highlight':
                            onToggleHighlight?.call();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        if (canEdit)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Editar Legenda'),
                              ],
                            ),
                          ),
                        if (canHighlight)
                          PopupMenuItem(
                            value: 'highlight',
                            child: Row(
                              children: [
                                Icon(
                                  photo.isHighlight
                                      ? Icons.star_border
                                      : Icons.star,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  photo.isHighlight
                                      ? 'Remover Destaque'
                                      : 'Destacar',
                                ),
                              ],
                            ),
                          ),
                        if (canDelete)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Deletar',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        child: Text(
                          photo.studentName[0].toUpperCase(),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              photo.studentName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              DateFormat(
                                "d 'de' MMM 'às' HH:mm",
                                'pt_BR',
                              ).format(photo.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (photo.caption != null && photo.caption!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      photo.caption!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
