import 'package:flutter/material.dart';

import 'constants.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accent.withValues(alpha: 0.12),
      ),
      child: Icon(
        Icons.pets,
        size: size * 0.55,
        color: AppColors.accent,
      ),
    );
  }
}

class DirtyDot extends StatelessWidget {
  const DirtyDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Unsaved changes',
      child: Tooltip(
        message: 'Unsaved changes',
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
