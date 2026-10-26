import 'package:flutter/material.dart';

import '../../app/bootstrap.dart';
import 'sources_screen.dart';
import 'naming_settings_screen.dart';
import 'storage_settings_screen.dart';
import 'application_settings_screen.dart';
import 'app_updates_screen.dart';
import 'settings_group.dart';

class UsageGuideScreen extends StatelessWidget {
  const UsageGuideScreen({
    super.key,
    required this.dependencies,
    this.onOpenTab,
  });
  final AppDependencies dependencies;
  final ValueChanged<int>? onOpenTab;

  static const _sections = <(String, List<String>)>[
    (
      '快速下载',
      [
        '从 X 分享帖子到 XDownloader，或在首页粘贴 x.com / twitter.com 链接；整段分享文案也可以。无需在应用中登录 X。',
        '点击粘贴按钮会直接解析；手动输入后点击解析按钮。选择“最佳画质”或下方分辨率开始下载。帖子包含多个视频时，可分别下载。',
      ],
    ),
    (
      '下载与历史',
      [
        '下载页显示进度与已保存视频。点封面可在应用内播放；长按进入多选，可批量收藏原帖链接、删除文件或移除记录。无原链接的旧记录无法加入收藏。',
        '“下载历史”保留成功、失败和取消记录，删除视频不会删除历史。点击历史记录可重新解析链接。网络或链接失效导致的失败任务，点击重试会通过保存的原帖重新获取地址，保留原视频序号和文件名，尽量匹配原画质；取消或移除记录可中断等待。',
        '下载与历史顶部可搜索文件名、原帖链接或帖子编号；多个关键词需同时匹配，历史搜索可与状态筛选组合。清空搜索可恢复列表。',
        '文件保存到 Download/XDownloader，可在“设置 → 下载与存储”查看位置。',
        '封面会保存在本机缓存中；“下载与存储 → 封面缓存”可调整大小上限、查看和清理，清理不会删除视频或记录。',
      ],
    ),
    (
      '播放器操作',
      [
        '单击视频显示或隐藏控件，播放时无操作会自动隐藏；双击暂停或继续。',
        '左右滑动调整进度；左侧上下滑动调亮度，右侧上下滑动调音量。播放器提供倍速、全屏和屏幕方向菜单。',
      ],
    ),
    (
      '收藏管理',
      [
        '首页爱心收藏当前帖子。收藏页可手动添加或从剪贴板添加链接，点击收藏会重新解析帖子。',
        '收藏顶部可搜索标题、链接或帖子编号，并与分类筛选组合；全选仅选择当前可见结果。搜索仅在本机进行，开启隐私模式会清空搜索内容。',
        '顶部分类栏可左右滑动、点按切换，“＋”可新增分类；筛选图标可选择排序或多选分类，显示所选分类的合集。“默认顺序”和“全部”可恢复默认视图。长按分类可改名或删除分类，删除后链接移到未分类；三个点菜单支持编辑单条收藏。',
        '点击三点菜单旁的红心取消收藏；长按条目进入多选，可全选当前分类下的条目并删除，随后可在 6 秒内点击“撤回”。三点菜单中的“详情”展示名称、链接与作者，点击对应行即可复制完整内容。取消收藏不会删除下载的视频。',
      ],
    ),
    (
      '下载源',
      [
        '首页“解析源”或“设置 → 规则设置 → 下载源”可切换、检测和管理来源。解析失败时可换源重试，也可开启失败后自动换源。',
        '内置 11 个来源，可手动选择 TWDown.net、TweetDL、TwSaver、TWMate 等来源。手选源始终优先，备用源按列表顺序尝试；各源菜单可提高或降低优先级，顺序在重启后保留。近期失败的备用源暂停尝试 2 分钟，单次自动换源最多尝试 5 个。',
        '检测来源时会检查视频是否可下载，结果区分“已验证视频”和“可解析，下载验证失败”。',
        '导出可选择单个或多个源并复制到剪贴板；导入会先预览，再勾选需要的源。源使用应用支持的 JSON 格式。',
      ],
    ),
    (
      '文件命名',
      [
        '“设置 → 规则设置 → 重命名规则”可选择原始标题或自定义规则。点选标签添加、长按左右拖动排序，可修改分隔符，页面会展示实际文件名样例。',
        '模板支持标题、作者、帖子编号、视频序号、分辨率，以及 {date}、{time}、{datetime}。时间取开始下载时的设备当地时间，仅影响之后的下载。',
      ],
    ),
    (
      '隐私与剪贴板',
      [
        '首页解析源旁的眼睛可快速开启隐私模式，开启后该按钮消失；可在首页空白内容区域连续三击进入解锁，或到“设置 → 应用设置”关闭。开启时清空原解析内容，仍可输入、粘贴和解析新链接；隐藏收藏与历史、模糊下载封面和名称，并阻止查看视频。',
        '应用设置可选择使用 4–6 位数字隐私 PIN 或无密码。设置密码后，关闭隐私模式时通过全屏数字键盘解锁（输入后点击确认），修改或移除密码均需验证当前密码；密码忘记后无法找回。',
        '隐私模式不会加密公共目录文件，系统文件管理器仍可访问。应用设置中也可控制自动读取剪贴板。',
        '“设置 → 应用设置 → 左右手模式”可调整操作按钮位置。左手模式将首页、列表、历史和播放器的侧边操作移到左侧；文字、底部导航顺序和设置页面保持原样，选择在重启后保留。',
      ],
    ),
    (
      '应用更新',
      [
        '在“设置 → 应用更新”选择稳定版或 Beta 渠道。开启启动检查后，每次启动检测新版，发现更新会弹窗，可直接下载。',
        '勾选“不再提醒”只关闭启动弹窗；手动检查始终显示结果。可在更新设置中重新开启“启动时提醒新版”。',
        '下载后校验安装包，再由 Android 确认安装；首次可能需要允许本应用安装更新。切回稳定版不会自动降级。',
      ],
    ),
  ];

  List<Widget> _actions(BuildContext context, String section) {
    Widget link(String key, String label, Widget screen) => TextButton.icon(
      key: Key(key),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => screen),
      ),
      icon: const Icon(Icons.arrow_forward),
      label: Text(label),
    );
    Widget tab(int index, String label) => TextButton.icon(
      key: Key('guide_tab_$index'),
      onPressed: () => onOpenTab!(index),
      icon: const Icon(Icons.arrow_forward),
      label: Text(label),
    );
    return switch (section) {
      '快速下载' => [if (onOpenTab != null) tab(0, '前往解析')],
      '下载与历史' => [
        if (onOpenTab != null) tab(1, '前往下载'),
        link(
          'guide_storage',
          '下载与存储',
          StorageSettingsScreen(repository: dependencies.downloads),
        ),
      ],
      '收藏管理' => [if (onOpenTab != null) tab(2, '前往收藏')],
      '下载源' => [
        link(
          'guide_sources',
          '管理下载源',
          SourcesScreen(
            repository: dependencies.sources,
            parser: dependencies.parser,
            readClipboard: dependencies.readClipboard,
          ),
        ),
      ],
      '文件命名' => [
        link(
          'guide_naming',
          '设置重命名规则',
          NamingSettingsScreen(repository: dependencies.settings),
        ),
      ],
      '隐私与剪贴板' => [
        link(
          'guide_application',
          '打开应用设置',
          ApplicationSettingsScreen(repository: dependencies.settings),
        ),
      ],
      '应用更新' => [
        link(
          'guide_updates',
          '打开更新设置',
          AppUpdatesScreen(repository: dependencies.updates),
        ),
      ],
      _ => [],
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('使用说明')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final section in _sections)
            SettingsPanel(
              title: section.$1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < section.$2.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Text(section.$2[i]),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _actions(context, section.$1),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
