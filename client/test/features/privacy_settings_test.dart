import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdownloader/app/app.dart';
import 'package:xdownloader/data/repositories/settings_repository.dart';
import 'package:xdownloader/features/settings/application_settings_screen.dart';
import 'package:xdownloader/features/settings/privacy_unlock_screen.dart';

import '../support/fake_privacy_passwords.dart';
import '../support/app_fixture.dart';

Future<SettingsRepository> showPrivacySettings(
  WidgetTester tester, {
  TestPrivacyPasswords? passwords,
}) async {
  final settings = SettingsRepository(
    MemorySnapshotStore(),
    passwords: passwords ?? TestPrivacyPasswords(),
  );
  await settings.initialize();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(home: ApplicationSettingsScreen(repository: settings)),
  );
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  testWidgets('PIN controls scale with phone width and stay centered', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = await showPrivacySettings(tester);
    var previousSize = 0.0;
    for (final width in [320.0, 400.0, 432.0]) {
      tester.view.physicalSize = Size(width, 890);
      await tester.pumpWidget(
        MaterialApp(home: PrivacyUnlockScreen(settings: settings)),
      );
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(Scaffold)).dx;
      for (final control in [
        find.text('输入隐私 PIN'),
        find.text('取消'),
        find.byKey(const Key('privacy_pin_2')),
        find.byKey(const Key('privacy_pin_0')),
      ]) {
        expect(tester.getCenter(control).dx, closeTo(center, .5));
      }
      final digit = tester.getSize(find.byKey(const Key('privacy_pin_2')));
      expect(digit.width, inInclusiveRange(width * .21, width * .26));
      expect(digit.width, closeTo(digit.height, .5));
      expect(digit.width, greaterThan(previousSize));
      previousSize = digit.width;
      final left = find.byKey(const Key('privacy_pin_delete'));
      final right = find.byKey(const Key('privacy_pin_confirm'));
      expect(tester.getSize(left), digit);
      expect(tester.getSize(right), digit);
      expect(
        (tester.getCenter(left).dx + tester.getCenter(right).dx) / 2,
        closeTo(center, .5),
      );
      expect(tester.takeException(), isNull);
    }
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '取消'),
    );
    expect(cancel.style?.backgroundColor?.resolve({})?.a, greaterThan(0));
  });

  testWidgets('optional privacy password can be created changed and removed', (
    tester,
  ) async {
    final settings = await showPrivacySettings(tester);
    await tester.tap(find.byKey(const Key('privacy_password_setting')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('privacy_new_password')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const Key('privacy_confirm_password')),
      '654321',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(settings.value.privacyPasswordHash, '');
    await tester.enterText(
      find.byKey(const Key('privacy_confirm_password')),
      '123456',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.value.privacyPasswordHash, isNotEmpty);
    await tester.tap(find.byKey(const Key('privacy_password_setting')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('privacy_current_password')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const Key('privacy_new_password')),
      '567890',
    );
    await tester.enterText(
      find.byKey(const Key('privacy_confirm_password')),
      '567890',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy_password_setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy_use_password')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy_new_password')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('privacy_current_password')),
      '123456',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('密码不正确'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('privacy_current_password')),
      '567890',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.value.privacyPasswordHash, '');
  });

  testWidgets(
    'password is required only when switching privacy off and cancel stays private',
    (tester) async {
      final settings = await showPrivacySettings(tester);
      await settings.setPrivacyPassword('123456');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_mode_switch')));
      await tester.pumpAndSettle();
      expect(settings.value.privacyMode, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('privacy_mode_switch')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('privacy_unlock_screen')), findsOneWidget);
      Future<void> pin(String digits) async {
        for (final digit in digits.split('')) {
          await tester.tap(find.byKey(Key('privacy_pin_$digit')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('privacy_pin_confirm')));
        await tester.pumpAndSettle();
      }

      await pin('000000');
      expect(find.text('密码不正确'), findsOneWidget);
      expect(settings.value.privacyMode, isTrue);
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const Key('privacy_pin_delete')));
        await tester.pumpAndSettle();
      }
      await pin('123456');
      expect(settings.value.privacyMode, isFalse);
      await settings.setPrivacyMode(true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_mode_switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_pin_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_pin_delete')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('PIN 输入'), findsOneWidget);
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(settings.value.privacyMode, isTrue);
      await tester.tap(find.byKey(const Key('privacy_mode_switch')));
      await tester.pumpAndSettle();
      await pin('123456');
      expect(settings.value.privacyMode, isFalse);
    },
  );

  for (final exit in ['back', 'cancel']) {
    testWidgets(
      'cancel during a PIN check prevents late verification from unlocking ($exit)',
      (tester) async {
        final passwords = TestPrivacyPasswords();
        final settings = await showPrivacySettings(
          tester,
          passwords: passwords,
        );
        await settings.setPrivacyPassword('1234');
        await settings.setPrivacyMode(true);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy_mode_switch')));
        await tester.pumpAndSettle();
        final gate = passwords.verifying = Completer<void>();
        for (final digit in '1234'.split('')) {
          await tester.tap(find.byKey(Key('privacy_pin_$digit')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('privacy_pin_confirm')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('privacy_pin_1')))
              .onPressed,
          isNotNull,
        );
        if (exit == 'back') {
          await tester.binding.handlePopRoute();
        } else {
          await tester.ensureVisible(find.text('取消'));
          await tester.pump();
          await tester.tap(find.text('取消'));
        }
        // Complete while the outgoing route is still mounted and animating.
        await tester.pump(const Duration(milliseconds: 30));
        gate.complete();
        await tester.pumpAndSettle();
        expect(settings.value.privacyMode, isTrue);
        expect(find.byKey(const Key('privacy_mode_switch')), findsOneWidget);
      },
    );
  }

  testWidgets('typing beyond a matching PIN invalidates an in-flight check', (
    tester,
  ) async {
    final passwords = TestPrivacyPasswords();
    final settings = await showPrivacySettings(tester, passwords: passwords);
    await settings.setPrivacyPassword('01234');
    await settings.setPrivacyMode(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy_mode_switch')));
    await tester.pumpAndSettle();
    for (final digit in '0123'.split('')) {
      await tester.tap(find.byKey(Key('privacy_pin_$digit')));
      await tester.pumpAndSettle();
    }
    final gate = passwords.verifying = Completer<void>();
    await tester.tap(find.byKey(const Key('privacy_pin_4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy_pin_confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy_pin_5')));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(settings.value.privacyMode, isTrue);
    expect(find.text('密码不正确'), findsNothing);
    final dots = find.descendant(
      of: find.bySemanticsLabel('PIN 输入'),
      matching: find.byType(Row),
    );
    expect(tester.widget<Row>(dots).children, hasLength(6));
    await tester.tap(find.byKey(const Key('privacy_pin_delete')));
    await tester.pumpAndSettle();
    expect(settings.value.privacyMode, isTrue);
    await tester.tap(find.byKey(const Key('privacy_pin_confirm')));
    await tester.pumpAndSettle();
    expect(settings.value.privacyMode, isFalse);
  });

  testWidgets(
    'private home remains usable without revealing favorites',
    (tester) => withAppFixture(tester, (fixture) async {
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('home_link_input')),
        'sensitive text',
      );
      await tester.tap(find.byKey(const Key('home_quick_privacy')));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.privacyMode, isTrue);
      expect(find.byKey(const Key('home_quick_privacy')), findsNothing);
      expect(find.textContaining('sensitive text'), findsNothing);
      expect(find.text('隐私模式已开启'), findsOneWidget);
      expect(find.byKey(const Key('home_link_input')), findsOneWidget);
      expect(find.byKey(const Key('favorite_current')), findsNothing);
      await fixture.favorites.add(
        'https://x.com/demo/status/123456',
        title: '已收藏的秘密标题',
      );
      fixture.clipboard = 'https://x.com/demo/status/123456';
      await tester.tap(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '粘贴'),
      );
      await tester.pumpAndSettle();
      expect(find.text('中文视频'), findsOneWidget);
      expect(fixture.parser.calls.last, contains('123456'));
      expect(find.byKey(const Key('favorite_current')), findsNothing);
      await fixture.settings.edit((s) => s.copyWith(autoClipboard: false));
      await tester.pumpAndSettle();
      expect(find.text('中文视频'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nav_favorites')));
      await tester.pumpAndSettle();
      expect(find.text('已收藏的秘密标题'), findsNothing);
      await tester.tap(find.byKey(const Key('nav_settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_mode_switch')));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.privacyMode, isFalse);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav_home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_quick_privacy')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('home_link_input')))
            .controller!
            .text,
        'https://x.com/demo/status/123456',
      );
    }),
  );

  for (final code in ['0123', '01234']) {
    testWidgets('$code PIN requires confirmation and only shows entered dots', (
      tester,
    ) async {
      final settings = await showPrivacySettings(tester);
      await settings.setPrivacyPassword(code);
      await settings.setPrivacyMode(true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_mode_switch')));
      await tester.pumpAndSettle();
      final dots = find.descendant(
        of: find.bySemanticsLabel('PIN 输入'),
        matching: find.byType(Row),
      );
      expect(tester.widget<Row>(dots).children, isEmpty);
      expect(find.textContaining('位请'), findsNothing);
      for (var index = 0; index < code.length; index++) {
        await tester.tap(find.byKey(Key('privacy_pin_${code[index]}')));
        await tester.pumpAndSettle();
        if (index < code.length - 1) {
          expect(tester.widget<Row>(dots).children, hasLength(index + 1));
        }
      }
      await tester.pump(const Duration(seconds: 2));
      expect(settings.value.privacyMode, isTrue);
      expect(tester.widget<Row>(dots).children, hasLength(code.length));
      await tester.tap(find.byKey(const Key('privacy_pin_confirm')));
      await tester.pumpAndSettle();
      expect(settings.value.privacyMode, isFalse);
    });
  }

  testWidgets(
    'only three consecutive taps on private empty hint open unlock',
    (tester) => withAppFixture(tester, (fixture) async {
      // The fixture hash is produced by the cheap test codec; this case only
      // opens and cancels the route, so no real PBKDF2 is needed.
      final hash = await TestPrivacyPasswords().hash('1234');
      await fixture.store.write('settings', {
        'privacyPasswordHash': hash,
        'privacyMode': true,
      });
      await fixture.settings.initialize();
      await tester.pumpWidget(
        XDownloaderApp(dependencies: fixture.dependencies),
      );
      await tester.pumpAndSettle();
      final hint = find.text('隐私模式已开启');
      // Blank space well outside the text and its former 24dp padding is tappable.
      final target = tester.getCenter(hint) + const Offset(120, -80);
      expect(tester.getRect(hint).contains(target), isFalse);
      await tester.tapAt(target);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 2; i++) {
        await tester.tapAt(target);
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const Key('privacy_unlock_screen')), findsNothing);
      await tester.tapAt(target);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy_unlock_screen')), findsOneWidget);
      await tester.ensureVisible(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.settings.value.privacyMode, isTrue);
      expect(hint, findsOneWidget);
    }),
  );

  for (final brightness in Brightness.values) {
    testWidgets('privacy password form fits 320dp doubled text $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = SettingsRepository(
        MemorySnapshotStore(),
        passwords: TestPrivacyPasswords(),
      );
      await settings.initialize();
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ApplicationSettingsScreen(repository: settings),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('privacy_password_setting')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy_password_setting')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      await settings.setPrivacyPassword('123456');
      await settings.setPrivacyMode(true);
      await tester.pumpAndSettle();
      final toggle = find.descendant(
        of: find.byKey(const Key('privacy_mode_switch')),
        matching: find.byType(Switch),
      );
      await Scrollable.ensureVisible(tester.element(toggle), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('privacy_pin_0')));
      expect(
        find.byKey(const Key('privacy_pin_0')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
