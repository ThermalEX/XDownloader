import 'package:flutter/material.dart';

import '../../core/models/media.dart';

class MediaResultView extends StatelessWidget {
  const MediaResultView({
    super.key,
    required this.result,
    required this.onDownload,
  });
  final MediaResult result;
  final Future<void> Function(MediaVariant) onDownload;
  String size(MediaVariant v) =>
      v.width > 0 && v.height > 0 ? '${v.width} × ${v.height}' : 'MP4';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(),
      const SizedBox(height: 12),
      Text(
        result.title.isEmpty ? '视频' : result.title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (result.author.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(result.author),
        ),
      const SizedBox(height: 12),
      ListTileTheme.merge(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          collapsedShape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          collapsedBackgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerLow,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: const Text('帖子信息'),
          children: [
            if (result.thumbnail != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Image.network(
                    '${result.thumbnail}',
                    errorBuilder: (_, error, stack) =>
                        const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text('${result.post.canonicalUrl}'),
              subtitle: Text('来源：${result.sourceId}'),
            ),
          ],
        ),
      ),
      for (final item in result.items) ...[
        const SizedBox(height: 20),
        Text(
          '视频 ${item.index}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => onDownload(item.variants.first),
          icon: const Icon(Icons.download),
          label: Text('最佳画质 · ${size(item.variants.first)}'),
        ),
        for (final variant in item.variants)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              label: '下载视频 ${item.index}，${size(variant)}',
              excludeSemantics: true,
              button: true,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onDownload(variant),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                size(variant),
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'MP4',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.download_outlined),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ],
  );
}
