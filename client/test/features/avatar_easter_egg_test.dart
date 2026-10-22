import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/core/models/app_settings.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/features/settings/about_screen.dart';
import 'package:xdownloader/features/settings/avatar_easter_egg.dart';

import '../support/app_fixture.dart';
import '../support/particle_canvas.dart';

const normal = 'assets/branding/app_icon.png';
const playful = 'assets/branding/playful_avatar.png';

class FailingSettingsStore extends MemorySnapshotStore {
  bool failWrites = false;
  @override
  Future<void> write(String key, Map<String, Object?> data) async {
    if (failWrites) throw StateError('fixture write failure');
    await super.write(key, data);
  }
}

String imageAsset(WidgetTester tester, String key) =>
    (tester.widget<Image>(find.byKey(Key(key))).image as ResizeImage)
        .imageProvider
        .toString();

void main() {
  testWidgets(
    'random batches do not form balanced opposing pairs or triangles',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvatarEasterEgg(
              settings: f.settings,
              random: math.Random(31),
            ),
          ),
        ),
      );
      var uneven = 0;
      for (var i = 0; i < 24; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump();
        final sample = snapshotParticles(tester);
        var total = Offset.zero;
        for (final position in sample.positions) {
          final fromCenter = position - sample.center;
          total += fromCenter / fromCenter.distance;
        }
        if ((total / sample.positions.length.toDouble()).distance > .22) {
          uneven++;
        }
        await tester.pumpAndSettle();
      }
      expect(uneven, greaterThanOrEqualTo(8));
    }),
  );
  testWidgets(
    'reactions cover all sides and keep only one active batch',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvatarEasterEgg(
              settings: f.settings,
              random: math.Random(23),
            ),
          ),
        ),
      );
      final quadrants = <(bool, bool)>{};
      for (var i = 0; i < 16; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 20));
        final sample = snapshotParticles(tester);
        for (final position in sample.positions) {
          final delta = position - sample.center;
          quadrants.add((delta.dx < 0, delta.dy < 0));
        }
        expect(
          find
              .byWidgetPredicate(
                (w) =>
                    w is CustomPaint &&
                    (w.key == const Key('avatar_anger_burst') ||
                        w.key == const Key('avatar_heart_burst')),
              )
              .evaluate()
              .length,
          lessThanOrEqualTo(1),
        );
      }
      expect(quadrants, hasLength(4));
    }),
  );
  for (final hearts in [false, true]) {
    testWidgets(
      'random decorative accents join the main effect: hearts=$hearts',
      (tester) => withAppFixture(tester, (f) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AvatarEasterEgg(
                settings: f.settings,
                random: math.Random(47),
              ),
            ),
          ),
        );
        final colors = <Color>{};
        final styles = <PaintingStyle>{};
        var paragraphs = 0;
        var tremblingMarks = 0;
        for (var i = 0; i < 32; i++) {
          await f.settings.edit((s) => s.copyWith(playfulAvatar: hearts));
          await tester.tap(find.byKey(const Key('about_avatar_button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 160));
          if (f.settings.value.playfulAvatar != hearts) {
            await tester.pumpAndSettle();
            continue;
          }
          final sample = snapshotParticles(tester);
          expect(sample.positions.length, inInclusiveRange(2, 3));
          for (var a = 0; a < sample.positions.length; a++) {
            for (var b = a + 1; b < sample.positions.length; b++) {
              final left = sample.positions[a] - sample.center;
              final right = sample.positions[b] - sample.center;
              final dot =
                  (left.dx * right.dx + left.dy * right.dy) /
                  (left.distance * right.distance);
              expect(dot, lessThan(.9));
            }
          }
          colors.addAll(sample.colors);
          styles.addAll(sample.styles);
          paragraphs += sample.paragraphs;
          tremblingMarks += sample.tremblingMarks;
          await tester.pumpAndSettle();
        }
        if (hearts) {
          expect(paragraphs, greaterThan(0));
          expect(tremblingMarks, greaterThan(0));
          expect(
            styles,
            containsAll([PaintingStyle.stroke, PaintingStyle.fill]),
          );
        } else {
          // A separate accent color distinguishes the anger marks from steam.
          expect(colors.length, greaterThan(1));
          expect(paragraphs, 0);
        }
      }),
    );
  }
  for (final hearts in [false, true]) {
    testWidgets(
      'particles grow from tiny sizes and follow outward motion: hearts=$hearts',
      (tester) => withAppFixture(tester, (f) async {
        await f.settings.edit((s) => s.copyWith(playfulAvatar: hearts));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AvatarEasterEgg(
                settings: f.settings,
                random: math.Random(17),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump();
        final early = snapshotParticles(tester);
        await tester.pump(const Duration(milliseconds: 360));
        final later = snapshotParticles(tester);
        for (var i = 0; i < early.positions.length; i++) {
          expect(later.scales[i], greaterThan(early.scales[i] * 5));
          final displacement = later.positions[i] - early.positions[i];
          final spawnFromCenter = early.positions[i] - early.center;
          expect(
            displacement.dx * spawnFromCenter.dx +
                displacement.dy * spawnFromCenter.dy,
            greaterThan(0),
          );
          if (!hearts) {
            final heading = Offset(
              math.cos(later.rotations[i]),
              math.sin(later.rotations[i]),
            );
            expect(
              (heading - displacement / displacement.distance).distance,
              lessThan(.000001),
            );
          }
        }
      }),
    );
  }

  testWidgets(
    'seeded taps vary count size position and direction without repaint jitter',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AvatarEasterEgg(
              settings: f.settings,
              random: math.Random(42),
            ),
          ),
        ),
      );
      final counts = <int>{};
      final origins = <Offset>{};
      final scales = <double>{};
      final rotations = <double>{};
      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 80));
        final first = snapshotParticles(tester);
        final repeatedPaint = snapshotParticles(tester);
        expect(repeatedPaint.positions, first.positions);
        expect(repeatedPaint.scales, first.scales);
        expect(repeatedPaint.rotations, first.rotations);
        counts.add(first.positions.length);
        origins.addAll(first.positions);
        scales.addAll(first.scales);
        rotations.addAll(first.rotations);
        await tester.pumpAndSettle();
      }
      expect(counts, {2, 3});
      expect(origins.length, greaterThan(15));
      expect(scales.length, greaterThan(15));
      expect(rotations.length, greaterThan(15));
    }),
  );

  testWidgets(
    'reduced motion keeps particle position and size static',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: AvatarEasterEgg(
                settings: f.settings,
                random: math.Random(42),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pump();
      final first = snapshotParticles(tester);
      await tester.pump(const Duration(milliseconds: 120));
      final later = snapshotParticles(tester);
      expect(later.positions, first.positions);
      expect(later.scales, first.scales);
    }),
  );
  testWidgets(
    'a tap emits a small sparse cluster instead of four fixed puffs',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(dependencies: f.dependencies)),
      );
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pump(const Duration(milliseconds: 160));
      final paint = tester.widget<CustomPaint>(
        find.byKey(const Key('avatar_anger_burst')),
      );
      final canvas = ParticleCanvas();
      paint.painter!.paint(canvas, const Size(216, 176));
      expect(canvas.positions.length, inInclusiveRange(2, 3));
    }),
  );
  test(
    'old settings retain normal avatar and selection survives a round trip',
    () {
      final old = AppSettings.fromJson({'privacyMode': true});
      expect(old.playfulAvatar, false);
      final restored = AppSettings.fromJson(
        old.copyWith(playfulAvatar: true).toJson(),
      );
      expect(restored.playfulAvatar, true);
      expect(restored.privacyMode, true);
    },
  );
  testWidgets(
    'six taps switch both avatars and persist without losing settings',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(XDownloaderApp(dependencies: f.dependencies));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AboutScreen(dependencies: f.dependencies),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.bySemanticsLabel('XDownloader 图标'));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(imageAsset(tester, 'about_avatar_image'), contains(normal));
      await tester.tap(find.bySemanticsLabel('XDownloader 图标'));
      await f.settings.edit((s) => s.copyWith(privacyMode: true));
      await tester.pumpAndSettle();
      expect(imageAsset(tester, 'about_avatar_image'), contains(playful));
      final restored = SettingsRepository(f.store);
      await restored.initialize();
      expect(restored.value.toJson()['playfulAvatar'], true);
      expect(restored.value.privacyMode, true);
      restored.dispose();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(imageAsset(tester, 'home_empty_art'), contains(playful));
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const Key('home_empty_art')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, .35);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AboutScreen(dependencies: f.dependencies),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.bySemanticsLabel('XDownloader 图标'));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();
      expect(imageAsset(tester, 'about_avatar_image'), contains(normal));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(imageAsset(tester, 'home_empty_art'), contains(normal));
    }),
  );

  testWidgets(
    'leaving About resets incomplete count and disposes active effects',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(dependencies: f.dependencies)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.bySemanticsLabel('XDownloader 图标'));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(dependencies: f.dependencies)),
      );
      await tester.tap(find.bySemanticsLabel('XDownloader 图标'));
      await tester.pumpAndSettle();
      expect(imageAsset(tester, 'about_avatar_image'), contains(normal));
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'rapid taps emit the correct effects over two complete cycles',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(dependencies: f.dependencies)),
      );
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pump();
      expect(find.byKey(const Key('avatar_anger_burst')), findsOneWidget);
      for (var i = 1; i < 6; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byKey(const Key('avatar_heart_burst')), findsOneWidget);
      expect(f.settings.value.playfulAvatar, true);
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pump();
      expect(find.byKey(const Key('avatar_heart_burst')), findsOneWidget);
      for (var i = 1; i < 6; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(f.settings.value.playfulAvatar, false);
      expect(find.byKey(const Key('avatar_anger_burst')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar_anger_burst')), findsNothing);
      expect(find.byKey(const Key('avatar_heart_burst')), findsNothing);
      expect(tester.takeException(), isNull);
    }),
  );

  testWidgets(
    'opening another About page resets the partial tap cycle',
    (tester) => withAppFixture(tester, (f) async {
      await tester.pumpWidget(
        MaterialApp(home: AboutScreen(dependencies: f.dependencies)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.byKey(const Key('usage_guide_entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pumpAndSettle();
      expect(f.settings.value.playfulAvatar, false);
    }),
  );

  testWidgets(
    'a failed save retains the portrait and the next tap retries',
    (tester) => withAppFixture(tester, (f) async {
      final store = FailingSettingsStore();
      final settings = SettingsRepository(store);
      await settings.initialize();
      // A dedicated repository lets this test simulate a durable write failure.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AvatarEasterEgg(settings: settings)),
        ),
      );
      store.failWrites = true;
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const Key('about_avatar_button')));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(settings.value.playfulAvatar, false);
      expect(imageAsset(tester, 'about_avatar_image'), contains(normal));
      expect(find.text('头像切换失败，请再试一次'), findsOneWidget);
      store.failWrites = false;
      await tester.tap(find.byKey(const Key('about_avatar_button')));
      await tester.pumpAndSettle();
      expect(settings.value.playfulAvatar, true);
      expect(imageAsset(tester, 'about_avatar_image'), contains(playful));
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    }),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '320dp doubled text and reduced motion: $brightness',
      (tester) => withAppFixture(tester, (f) async {
        await tester.binding.setSurfaceSize(const Size(320, 740));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 740),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: AboutScreen(dependencies: f.dependencies),
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.tap(find.byKey(const Key('about_avatar_button')));
          await tester.pump(const Duration(milliseconds: 30));
          final transforms = tester.widgetList<Transform>(
            find.ancestor(
              of: find.byKey(const Key('about_avatar_button')),
              matching: find.byType(Transform),
            ),
          );
          expect(transforms.every((t) => t.transform.isIdentity()), true);
        }
        await tester.pumpAndSettle();
        expect(imageAsset(tester, 'about_avatar_image'), contains(playful));
        expect(tester.takeException(), isNull);
      }),
    );
  }
}
