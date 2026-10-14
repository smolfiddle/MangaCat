import 'package:flutter/material.dart';

import '../../core/constants.dart';

class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.maxLength = 6});

  final int length;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(maxLength, (int index) {
        final filled = index < length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.accent : Colors.transparent,
            border: Border.all(
              color: filled ? AppColors.accent : AppColors.textSecondary,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }
}

class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final row in const <List<String>>[
            <String>['1', '2', '3'],
            <String>['4', '5', '6'],
            <String>['7', '8', '9'],
            <String>['', '0', '<'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: row.map((String key) {
                if (key.isEmpty) {
                  return const SizedBox(width: 88, height: 72);
                }
                if (key == '<') {
                  return _KeyButton(
                    onPressed: enabled ? onBackspace : null,
                    child: const Icon(Icons.backspace_outlined, size: 22),
                  );
                }
                return _KeyButton(
                  onPressed: enabled ? () => onDigit(key) : null,
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 72,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppShape.cardRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppShape.cardRadius),
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class Shaker extends StatefulWidget {
  const Shaker({super.key, required this.trigger, required this.child});

  final Object trigger;
  final Widget child;

  @override
  State<Shaker> createState() => _ShakerState();
}

class _ShakerState extends State<Shaker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final Animation<double> _offset = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: -12), weight: 1),
    TweenSequenceItem<double>(tween: Tween<double>(begin: -12, end: 12), weight: 2),
    TweenSequenceItem<double>(tween: Tween<double>(begin: 12, end: -8), weight: 2),
    TweenSequenceItem<double>(tween: Tween<double>(begin: -8, end: 8), weight: 2),
    TweenSequenceItem<double>(tween: Tween<double>(begin: 8, end: 0), weight: 1),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant Shaker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(_offset.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
