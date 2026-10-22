import 'package:flutter/material.dart';

import 'settings_group.dart';

class UsageGuideScreen extends StatelessWidget {
  const UsageGuideScreen({super.key});

  static const _sections = <(String, List<String>)>[
    (
      '快速下载',
      [
        '从 X 分享帖子到 XDownloader，或在首页粘贴 x.com / twitter.com 链接；整段分享文案也可以。无需在应用中登录 X。',
        '点击输入栏右侧的解析按钮，选择“最佳画质”或下方分辨率开始下载。帖子包含多个视频时，可分别下载。',
      ],
    ),
    (
      '下载与历史',
      [
        '下载页显示进度与已保存视频。点封面可在应用内播放；长按进入多选，可批量删除文件。',
        '“下载历史”保留成功、失败和取消记录，删除视频不会删除历史。点击历史记录可重新解析链接。',
        '文件保存到 Download/XDownloader，可在“设置 → 下载与存储”查看位置。',
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
        '筛选图标可选择排序与分类；“默认顺序”和“全部”可恢复默认视图。三个点菜单支持改名和分类。',
        '点击列表前方红心取消收藏，随后可在消息中点击“撤回”。取消收藏不会删除下载的视频。',
      ],
    ),
    (
      '下载源',
      [
        '首页“解析源”或“设置 → 规则设置 → 下载源”可切换、检测和管理来源。解析失败时可换源重试，也可开启失败后自动换源。',
        '导出可选择单个或多个源并复制到剪贴板；导入会先预览，再勾选需要的源。源使用应用支持的 JSON 格式。',
      ],
    ),
    (
      '文件命名',
      [
        '“设置 → 规则设置 → 重命名规则”可选择原始标题或自定义模板，页面会展示实际文件名样例。',
        '模板支持标题、作者、帖子编号、视频序号、分辨率，以及 {date}、{time}、{datetime}。时间取开始下载时的设备当地时间，仅影响之后的下载。',
      ],
    ),
    (
      '隐私与剪贴板',
      [
        '在“设置 → 应用设置”开启隐私模式，会模糊下载封面和名称、隐藏收藏与历史内容，并阻止查看视频。',
        '隐私模式不会加密公共目录文件，系统文件管理器仍可访问。应用设置中也可控制自动读取剪贴板。',
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
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
