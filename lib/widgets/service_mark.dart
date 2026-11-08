import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';
import '../theme/tokens.dart';

class ServiceMark extends StatelessWidget {
  const ServiceMark(this.kind, {super.key, this.size = 38});

  final IntegrationKind kind;
  final double size;

  static Color colorFor(IntegrationKind kind) => switch (kind) {
        IntegrationKind.github => Pal.text,
        IntegrationKind.vercel => Pal.text,
        IntegrationKind.cloudflare => const Color(0xFFF48120),
        IntegrationKind.expo => const Color(0xFFD9D3CA),
        IntegrationKind.tavily => const Color(0xFFEF6B54),
        IntegrationKind.supabase => const Color(0xFF3ECF8E),
      };

  static IconData iconFor(IntegrationKind kind) => switch (kind) {
        IntegrationKind.github => Icons.code_rounded,
        IntegrationKind.vercel => Icons.change_history_rounded,
        IntegrationKind.cloudflare => Icons.cloud_outlined,
        IntegrationKind.expo => Icons.phone_iphone_rounded,
        IntegrationKind.tavily => Icons.travel_explore_rounded,
        IntegrationKind.supabase => Icons.storage_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(kind);
    final asset = switch (kind) {
      IntegrationKind.github => 'assets/icons/github.svg',
      IntegrationKind.vercel => 'assets/icons/vercel.svg',
      IntegrationKind.cloudflare => 'assets/icons/cloudflarepages.svg',
      _ => null,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Center(
        child: asset == null
            ? Icon(iconFor(kind), size: size * 0.46, color: color)
            : SvgPicture.asset(
                asset,
                width: size * 0.48,
                height: size * 0.48,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              ),
      ),
    );
  }
}
