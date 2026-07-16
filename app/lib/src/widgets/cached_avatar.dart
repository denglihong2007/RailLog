import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CachedAvatar extends StatelessWidget {
  const CachedAvatar({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.size,
    this.backgroundColor,
    this.textStyle,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? backgroundColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final fallback = Center(
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: textStyle),
    );

    return ClipOval(
      child: ColoredBox(
        color:
            backgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SizedBox.square(
          dimension: size,
          child: url.isEmpty
              ? fallback
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  maxWidthDiskCache: 256,
                  maxHeightDiskCache: 256,
                  fadeInDuration: const Duration(milliseconds: 150),
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
