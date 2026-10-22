import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/branding_assets.dart';
import '../../app/favorite_icon.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/storage/serial_queue.dart';

/// Only the selected portrait is persisted; a partial six-tap cycle is local.
class AvatarEasterEgg extends StatefulWidget {
  const AvatarEasterEgg({super.key, required this.settings, this.random});
  final SettingsRepository settings;
  final math.Random? random;

  @override
  State<AvatarEasterEgg> createState() => _AvatarEasterEggState();
}

class _AvatarEasterEggState extends State<AvatarEasterEgg>
    with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  final _taps = SerialQueue();
  late final _random = widget.random ?? math.Random();
  final _bursts = <({int id, bool hearts, List<_Particle> particles})>[];
  int _count = 0, _nextId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pushing the guide/log covers About without disposing its state.
    if (ModalRoute.isCurrentOf(context) == false) {
      _count = 0;
      _bursts.clear();
      _shake.reset();
    }
    for (final asset in [normalAvatarAsset, playfulAvatarAsset]) {
      precacheImage(ResizeImage(AssetImage(asset), width: 384), context);
    }
  }

  Future<void> _tap() => _taps.run(() async {
    if (!mounted || ModalRoute.isCurrentOf(context) == false) return;
    if (_count < 5) {
      _count++;
    } else {
      try {
        await widget.settings.edit(
          (s) => s.copyWith(playfulAvatar: !s.playfulAvatar),
        );
        _count = 0;
      } catch (_) {
        // Keep five taps so the next tap retries; emit the unchanged mode.
        if (mounted && ModalRoute.isCurrentOf(context) != false) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('头像切换失败，请再试一次')));
        }
      }
    }
    if (!mounted || ModalRoute.isCurrentOf(context) == false) return;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    setState(() {
      // Bound concurrent effects even when taps arrive faster than animation.
      _bursts.clear();
      _bursts.add((
        id: _nextId++,
        hearts: widget.settings.value.playfulAvatar,
        particles: _Particle.generate(
          _random,
          hearts: widget.settings.value.playfulAvatar,
        ),
      ));
    });
    if (!reducedMotion) _shake.forward(from: 0);
  });

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 216,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _shake,
            child: Semantics(
              container: true,
              button: true,
              label: 'XDownloader 图标',
              child: InkResponse(
                key: const Key('about_avatar_button'),
                onTap: _tap,
                radius: 64,
                containedInkWell: true,
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                child: ListenableBuilder(
                  listenable: widget.settings,
                  builder: (context, _) => Image.asset(
                    appAvatarAsset(widget.settings.value.playfulAvatar),
                    key: const Key('about_avatar_image'),
                    width: 120,
                    height: 120,
                    cacheWidth: 384,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            builder: (context, child) {
              final t = _shake.value;
              final wave = reducedMotion
                  ? 0.0
                  : math.sin(t * math.pi * 8) * (1 - t);
              return Transform.translate(
                offset: Offset(wave * 5, 0),
                child: Transform.rotate(angle: wave * .045, child: child),
              );
            },
          ),
          for (final burst in _bursts)
            Positioned.fill(
              key: ValueKey(burst.id),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: _AvatarBurst(
                    hearts: burst.hearts,
                    reducedMotion: reducedMotion,
                    particles: burst.particles,
                    onComplete: () {
                      if (mounted) setState(() => _bursts.remove(burst));
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarBurst extends StatefulWidget {
  const _AvatarBurst({
    required this.hearts,
    required this.reducedMotion,
    required this.particles,
    required this.onComplete,
  });
  final bool hearts, reducedMotion;
  final List<_Particle> particles;
  final VoidCallback onComplete;

  @override
  State<_AvatarBurst> createState() => _AvatarBurstState();
}

class _AvatarBurstState extends State<_AvatarBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.reducedMotion ? 220 : 800),
    );
    _animation.forward().whenCompleteOrCancel(() {
      if (mounted && _animation.isCompleted) widget.onComplete();
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) => CustomPaint(
      key: Key(widget.hearts ? 'avatar_heart_burst' : 'avatar_anger_burst'),
      painter: _BurstPainter(
        progress: _animation.value,
        hearts: widget.hearts,
        reducedMotion: widget.reducedMotion,
        particles: widget.particles,
        color: widget.hearts
            ? savedHeartColor(context)
            : Theme.of(context).colorScheme.onSurfaceVariant,
        accent: savedHeartColor(context),
      ),
    ),
  );
}

/// Sample randomness once per tap; repainting must not move the spawn points.
enum _ParticleKind { steam, vein, heart, word, tremble }

class _Particle {
  const _Particle(
    this.origin,
    this.direction,
    this.distance,
    this.size,
    this.tilt,
    this.kind,
    this.variation,
  );
  final Offset origin, direction;
  final double distance, size, tilt;
  final _ParticleKind kind;
  final int variation;

  static List<_Particle> generate(math.Random random, {required bool hearts}) {
    final count = 2 + random.nextInt(2);
    final headings = <double>[];
    return List.generate(count, (i) {
      final heading = _randomHeading(random, headings);
      headings.add(heading);
      final direction = Offset(math.cos(heading), math.sin(heading));
      final secondary = hearts
          ? const [
              _ParticleKind.word,
              _ParticleKind.tremble,
              _ParticleKind.heart,
            ][random.nextInt(3)]
          : (random.nextDouble() < .65
                ? _ParticleKind.vein
                : _ParticleKind.steam);
      return _Particle(
        Offset(direction.dx * 58, direction.dy * 52) +
            Offset(random.nextDouble() * 8 - 4, random.nextDouble() * 8 - 4),
        direction,
        18 + random.nextDouble() * 14,
        i == 2 ? 10 + random.nextDouble() * 5 : 18 + random.nextDouble() * 12,
        random.nextDouble() * .8 - .4,
        i == 0
            ? (hearts ? _ParticleKind.heart : _ParticleKind.steam)
            : secondary,
        random.nextInt(3),
      );
    }, growable: false);
  }

  // Sample any remaining angle, excluding only a small gap around each used
  // direction. No equal spacing, opposing pairs, or cyclic sector layout.
  static double _randomHeading(math.Random random, List<double> used) {
    const turn = 2 * math.pi;
    if (used.isEmpty) return random.nextDouble() * turn;
    final sorted = [...used]..sort();
    final free = <(double, double)>[];
    for (var i = 0; i < sorted.length; i++) {
      final start = sorted[i] + .75;
      final end =
          sorted[(i + 1) % sorted.length] +
          (i == sorted.length - 1 ? turn : 0) -
          .75;
      if (end > start) free.add((start, end));
    }
    var ticket =
        random.nextDouble() *
        free.fold(0.0, (sum, span) => sum + span.$2 - span.$1);
    for (final span in free) {
      final length = span.$2 - span.$1;
      if (ticket < length) return (span.$1 + ticket) % turn;
      ticket -= length;
    }
    return free.last.$2 % turn;
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({
    required this.progress,
    required this.hearts,
    required this.reducedMotion,
    required this.particles,
    required this.color,
    required this.accent,
  });
  final double progress;
  final bool hearts, reducedMotion;
  final List<_Particle> particles;
  final Color color, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final travel = reducedMotion ? 0.0 : Curves.easeOut.transform(progress);
    final growth = reducedMotion
        ? .8
        : .08 +
              .92 *
                  Curves.easeOutCubic.transform(
                    (progress / .75).clamp(0.0, 1.0),
                  );
    final fade =
        (progress / .12).clamp(0.0, 1.0) *
        ((1 - progress) / .55).clamp(0.0, 1.0);
    final paint = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final particle in particles) {
      final outlined =
          particle.kind != _ParticleKind.heart || particle.variation == 2;
      paint
        ..color = (particle.kind == _ParticleKind.steam ? color : accent)
            .withValues(alpha: .85 * fade)
        ..style = outlined ? PaintingStyle.stroke : PaintingStyle.fill;
      final position =
          Offset(size.width / 2, size.height / 2) +
          particle.origin +
          particle.direction * (travel * particle.distance);
      canvas.save();
      canvas.translate(position.dx, position.dy);
      // Steam is drawn facing +X, with its trail behind it toward the avatar.
      canvas.rotate(
        hearts
            ? particle.tilt
            : math.atan2(particle.direction.dy, particle.direction.dx),
      );
      canvas.scale(
        particle.size *
            growth /
            (particle.kind == _ParticleKind.steam ? 52 : 32),
      );
      switch (particle.kind) {
        case _ParticleKind.steam:
          canvas.drawPath(_steam, paint);
        case _ParticleKind.vein:
          canvas.drawPath(_vein, paint);
        case _ParticleKind.heart:
          canvas.drawPath(_hearts[particle.variation], paint);
          if (!outlined) {
            canvas.drawPath(
              _highlight,
              Paint()
                ..color = Colors.white.withValues(alpha: fade * .7)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.2
                ..strokeCap = StrokeCap.round,
            );
          }
        case _ParticleKind.word:
          _paintWord(
            canvas,
            const ['ドキッ', 'きゅん', 'ふにゃ'][particle.variation],
            paint.color,
          );
        case _ParticleKind.tremble:
          canvas.drawPath(_trembles[particle.variation], paint);
      }
      canvas.restore();
    }
  }

  static void _paintWord(Canvas canvas, String word, Color color) {
    final text = String.fromCharCodes(word.runes).split('').join('\n');
    final outline = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 14,
          height: 1,
          fontWeight: FontWeight.w600,
          foreground: Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    final fill = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 14,
          height: 1,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: color.a),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    try {
      outline.layout();
      fill.layout();
      final offset = Offset(-outline.width / 2, -outline.height / 2);
      outline.paint(canvas, offset);
      fill.paint(canvas, offset);
    } finally {
      outline.dispose();
      fill.dispose();
    }
  }

  // The tapered tip points inward (-X); the lobed puff leads outward (+X).
  static final _steam = Path()
    ..moveTo(-25, 0)
    ..lineTo(-8, -8)
    ..cubicTo(-17, -20, -3, -26, 2, -18)
    ..cubicTo(0, -34, 20, -32, 19, -18)
    ..cubicTo(35, -22, 36, -2, 23, 1)
    ..cubicTo(33, 14, 14, 22, 9, 12)
    ..cubicTo(-1, 21, -14, 12, -8, 6)
    ..close()
    ..moveTo(-23, -7)
    ..lineTo(-15, -12)
    ..moveTo(-23, 7)
    ..lineTo(-15, 11);

  static final _vein = Path()
    ..moveTo(-13, -3)
    ..quadraticBezierTo(-3, -3, -3, -13)
    ..moveTo(3, -13)
    ..quadraticBezierTo(3, -3, 13, -3)
    ..moveTo(13, 3)
    ..quadraticBezierTo(3, 3, 3, 13)
    ..moveTo(-3, 13)
    ..quadraticBezierTo(-3, 3, -13, 3);

  static final _hearts = [
    Path()
      ..moveTo(-2, 14)
      ..cubicTo(-29, 1, -17, -20, -4, -9)
      ..cubicTo(7, -32, 27, -21, 14, -2)
      ..cubicTo(7, 7, 2, 10, -2, 14)
      ..close(),
    Path()
      ..moveTo(-1, 15)
      ..cubicTo(-8, 2, -26, -4, -17, -14)
      ..cubicTo(-11, -23, -2, -12, 0, -8)
      ..cubicTo(1, -27, 23, -31, 20, -10)
      ..cubicTo(17, 2, 7, 7, -1, 15)
      ..close(),
    Path()
      ..moveTo(-9, 13)
      ..lineTo(-12, -6)
      ..cubicTo(-17, -25, -2, -26, 1, -11)
      ..cubicTo(13, -31, 32, -15, 15, 0)
      ..close(),
  ];
  static final _highlight = Path()
    ..moveTo(7, -12)
    ..quadraticBezierTo(10, -17, 13, -16);
  static final _trembles = [
    Path()
      ..moveTo(-12, -12)
      ..lineTo(-8, -2)
      ..lineTo(-1, -8)
      ..lineTo(0, 6)
      ..lineTo(6, 2)
      ..lineTo(12, 13),
    Path()
      ..moveTo(-13, -8)
      ..quadraticBezierTo(-7, -18, -4, -6)
      ..quadraticBezierTo(0, 9, 4, -1)
      ..quadraticBezierTo(10, -12, 13, 10),
    Path()
      ..moveTo(-13, -11)
      ..lineTo(-9, 3)
      ..lineTo(-4, -2)
      ..lineTo(0, 13)
      ..moveTo(5, -14)
      ..lineTo(9, 0)
      ..lineTo(14, -5)
      ..lineTo(18, 9),
  ];

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.accent != accent ||
      oldDelegate.hearts != hearts ||
      !identical(oldDelegate.particles, particles) ||
      oldDelegate.reducedMotion != reducedMotion;
}
