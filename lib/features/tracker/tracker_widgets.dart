import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/models/entry.dart';

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 10});

  final EntryStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: ${status.label}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: statusColorOf(status),
        ),
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.compact = false,
    this.onChanged,
  });

  final int rating;
  final bool compact;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 12.0 : 24.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(5, (int index) {
        final value = index + 1;
        final filled = value <= rating;
        final icon = Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: filled ? AppColors.accent : AppColors.textSecondary,
        );
        if (onChanged == null) return icon;
        return IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => onChanged!(rating == value ? 0 : value),
          icon: icon,
        );
      }),
    );
  }
}

class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.entry,
    required this.showId,
    required this.advanced,
    required this.selected,
    required this.selectionMode,
    this.onTap,
    this.onLongPress,
  });

  final Entry entry;
  final bool showId;
  final bool advanced;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.surfaceVariant : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: AppShape.rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: selected ? AppColors.accent : AppColors.textSecondary,
                    ),
                  ),
                if (showId)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '#${entry.id}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (entry.artist.isNotEmpty)
                        Text(
                          entry.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (advanced && entry.rating > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: RatingStars(rating: entry.rating, compact: true),
                  ),
                const SizedBox(width: 12),
                StatusDot(status: entry.status),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyCat extends StatelessWidget {
  const EmptyCat({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.pets, size: 56, color: AppColors.textSecondary),
        const SizedBox(height: 16),
        Text(
          message ?? 'Nothing here yet.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
      ],
    );
  }
}
