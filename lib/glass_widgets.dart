import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Crore-Budget Frosted Glassmorphism Design System & Ultra-Premium Song Cards
class GlassBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color tintColor;
  final Color borderColor;
  final double borderWidth;
  final List<BoxShadow>? shadows;

  const GlassBox({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    this.blur = 14.0,
    this.tintColor = const Color(0xFF10192E),
    this.borderColor = const Color(0x3800E5FF),
    this.borderWidth = 1.1,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(0.38),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tintColor.withOpacity(0.82),
                  tintColor.withOpacity(0.56),
                ],
              ),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Animated 4-Bar Neon Equalizer Indicator for Currently Playing Song Card
class AnimatedEqualizerBars extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const AnimatedEqualizerBars({
    super.key,
    required this.isPlaying,
    this.color = const Color(0xFF00E5FF),
  });

  @override
  State<AnimatedEqualizerBars> createState() => _AnimatedEqualizerBarsState();
}

class _AnimatedEqualizerBarsState extends State<AnimatedEqualizerBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPlaying) {
      return Icon(Icons.equalizer, color: widget.color, size: 18);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final double v = _ctrl.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            final double phase = (v + i * 0.27) % 1.0;
            final double h = 5.0 + 13.0 * (0.5 + 0.5 * sin(phase * 2 * pi));
            return Container(
              width: 3.0,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.0),
              decoration: BoxDecoration(
                color: i.isEven ? widget.color : Colors.amberAccent,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Ultra-Premium Glassmorphic Song Card with Category Pill, Bitrate Master Badge, BPM & Glow Controls
class PremiumGlassSongCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> track;
  final bool isPlayingThis;
  final bool isActivelyPlaying;
  final bool isFavorite;
  final bool isOffline;
  final String? offlineCategory;
  final int? downloadProgressPct;
  final VoidCallback onPlayTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onDownloadOrCategoryTap;
  final VoidCallback onMoreOptionsTap;

  const PremiumGlassSongCard({
    super.key,
    required this.index,
    required this.track,
    required this.isPlayingThis,
    required this.isActivelyPlaying,
    required this.isFavorite,
    required this.isOffline,
    this.offlineCategory,
    this.downloadProgressPct,
    required this.onPlayTap,
    required this.onFavoriteTap,
    required this.onDownloadOrCategoryTap,
    required this.onMoreOptionsTap,
  });

  int _estimateBpm(String id, String title) {
    final String lower = title.toLowerCase();
    if (lower.contains('funk') || lower.contains('phonk')) return 130;
    if (lower.contains('dj') || lower.contains('remix')) return 128;
    if (lower.contains('mass') || lower.contains('dhol') || lower.contains('maar')) return 124;
    final int hash = id.hashCode.abs();
    return 96 + (hash % 34);
  }

  @override
  Widget build(BuildContext context) {
    final String title = (track['title'] ?? 'Track').toString();
    final String artist = (track['artist'] ?? 'Artist').toString();
    final String cover = (track['cover'] ?? '').toString();
    final String durationStr = (track['durationStr'] ?? 'Full').toString();
    final String id = (track['id'] ?? '').toString();
    final int bpm = _estimateBpm(id, title);

    return GestureDetector(
      onTap: onPlayTap,
      onLongPress: onMoreOptionsTap,
      child: GlassBox(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        borderRadius: 16,
        blur: 12,
        tintColor: isPlayingThis ? const Color(0xFF172C5C) : const Color(0xFF0E1729),
        borderColor: isPlayingThis
            ? const Color(0xFF00E5FF)
            : (isOffline ? const Color(0x6600E676) : const Color(0x28FFFFFF)),
        borderWidth: isPlayingThis ? 1.6 : 1.0,
        shadows: isPlayingThis
            ? [
                BoxShadow(
                  color: const Color(0xFF00E5FF).withOpacity(0.28),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
        child: Row(
          children: [
            // 1. High-Res Album Art + Rank Badge + Duration Overlay
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isPlayingThis ? Colors.amberAccent : Colors.white24,
                      width: isPlayingThis ? 1.5 : 0.8,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: cover.startsWith('http')
                        ? Image.network(
                            cover,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallbackArt(),
                          )
                        : _fallbackArt(),
                  ),
                ),
                if (isPlayingThis)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.52),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: AnimatedEqualizerBars(isPlaying: isActivelyPlaying),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.84),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Text(
                    durationStr,
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: Color(0xFF00E676),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFAB00), Color(0xFFFF6D00)],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 11),

            // 2. Song Details + Pro Micro-Badges (320kbps, BPM, Offline Category Pill)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      letterSpacing: 0.1,
                      color: isPlayingThis ? Colors.amberAccent : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2.5),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isPlayingThis ? const Color(0xFF00E5FF) : Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _microPill(
                        isOffline ? '⚡ OFFLINE 320K' : '320K MASTER',
                        isOffline ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
                      ),
                      _microPill('$bpm BPM', Colors.amberAccent),
                      if (offlineCategory != null && offlineCategory!.isNotEmpty)
                        GestureDetector(
                          onTap: onDownloadOrCategoryTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white38, width: 0.6),
                            ),
                            child: Text(
                              '📂 $offlineCategory',
                              style: const TextStyle(
                                fontSize: 8.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. Action Buttons Cluster
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Favorite',
                  icon: Icon(
                    isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFavorite ? Colors.pinkAccent : Colors.white60,
                    size: 20,
                  ),
                  onPressed: onFavoriteTap,
                ),
                if (downloadProgressPct != null)
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            value: (downloadProgressPct! / 100.0).clamp(0.05, 1.0),
                            strokeWidth: 2.5,
                            color: Colors.amberAccent,
                          ),
                        ),
                        Text(
                          '$downloadProgressPct%',
                          style: const TextStyle(
                            fontSize: 7.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: isOffline ? 'Change Offline Category' : 'Download to Category Folder',
                    icon: Icon(
                      isOffline ? Icons.folder_special_rounded : Icons.download_for_offline_rounded,
                      color: isOffline ? Colors.amberAccent : const Color(0xFF00E676),
                      size: 22,
                    ),
                    onPressed: onDownloadOrCategoryTap,
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
                  tooltip: 'Song Options & Lyrics',
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white60, size: 19),
                  onPressed: onMoreOptionsTap,
                ),
                const SizedBox(width: 2),
                GestureDetector(
                  onTap: onPlayTap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: (isPlayingThis && isActivelyPlaying)
                            ? [const Color(0xFFFFAB00), const Color(0xFFFF6D00)]
                            : [const Color(0xFF00E5FF), const Color(0xFF2979FF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ((isPlayingThis && isActivelyPlaying)
                                  ? Colors.amber
                                  : const Color(0xFF00E5FF))
                              .withOpacity(0.45),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      (isPlayingThis && isActivelyPlaying)
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _microPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.45), width: 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8.2,
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _fallbackArt() {
    return Container(
      width: 56,
      height: 56,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
        ),
      ),
      child: const Icon(Icons.music_note_rounded, color: Color(0xFF00E5FF), size: 26),
    );
  }
}
