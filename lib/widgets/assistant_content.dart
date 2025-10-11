import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:markdown/markdown.dart' as md;

class AssistantContent extends StatelessWidget {
  final String content;
  const AssistantContent(this.content, {super.key});

  MarkdownStyleSheet _mdStyle(BuildContext context) {
    final cuTheme = cupertino.CupertinoTheme.of(context);
    return MarkdownStyleSheet.fromCupertinoTheme(cuTheme);
  }

  @override
  Widget build(BuildContext context) {
    final style = _mdStyle(context);
    const fence = '```';
    final builders = {'code': _InlineCodeBuilder()};
    final children = <Widget>[];
    int cursor = 0;
    while (true) {
      final start = content.indexOf(fence, cursor);
      if (start == -1) {
        final tail = content.substring(cursor);
        if (tail.trim().isNotEmpty) {
          children.add(
            MarkdownBody(
              data: tail.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
        }
        break;
      }
      if (start > cursor) {
        final before = content.substring(cursor, start);
        if (before.trim().isNotEmpty) {
          children.add(
            MarkdownBody(
              data: before.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
        }
      }

      final int lineStart = start > 0
          ? content.lastIndexOf('\n', start - 1) + 1
          : 0;
      final linePrefix = content.substring(lineStart, start);
      final isBlockquoteFence = linePrefix.trimLeft().startsWith('>');

      final infoLineEnd = content.indexOf('\n', start + fence.length);
      if (infoLineEnd == -1) {
        final tail = content.substring(start);
        if (tail.trim().isNotEmpty) {
          children.add(
            MarkdownBody(
              data: tail.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
        }
        break;
      }

      if (isBlockquoteFence) {
        int searchPos = infoLineEnd + 1;
        int endFence = -1;
        while (true) {
          final nextFence = content.indexOf(fence, searchPos);
          if (nextFence == -1) break;
          final ls = content.lastIndexOf('\n', nextFence - 1) + 1;
          final prefix = content.substring(ls, nextFence);
          if (prefix.trimLeft().startsWith('>')) {
            endFence = nextFence;
            break;
          }
          searchPos = nextFence + fence.length;
        }
        if (endFence == -1) {
          final tail = content.substring(lineStart);
          children.add(
            MarkdownBody(
              data: tail.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
          break;
        } else {
          final block = content.substring(lineStart, endFence + fence.length);
          children.add(
            MarkdownBody(
              data: block.trim(),
              styleSheet: style,
              builders: builders,
            ),
          );
          cursor = endFence + fence.length;
          continue;
        }
      }

      final info = content.substring(start + fence.length, infoLineEnd).trim();
      final end = content.indexOf(fence, infoLineEnd + 1);
      if (end == -1) {
        final code = content.substring(infoLineEnd + 1);
        children.add(
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade200,
            child: SelectableHighlight(
              code: code,
              language: info.isEmpty ? 'plaintext' : info,
            ),
          ),
        );
        break;
      } else {
        final code = content.substring(infoLineEnd + 1, end);
        children.add(
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey.shade200,
            child: SelectableHighlight(
              code: code,
              language: info.isEmpty ? 'plaintext' : info,
            ),
          ),
        );
        cursor = end + fence.length;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class SelectableHighlight extends StatelessWidget {
  final String code;
  final String language;
  const SelectableHighlight({
    super.key,
    required this.code,
    required this.language,
  });

  TextSpan _buildSpan(List<hl.Node> nodes) {
    final spans = <TextSpan>[];
    TextStyle? styleFor(String? className) {
      if (className == null) return null;
      final parts = className.split(' ');
      TextStyle? merged;
      for (final p in parts) {
        final s = githubTheme[p];
        if (s != null) merged = (merged ?? const TextStyle()).merge(s);
      }
      return merged;
    }

    void walk(hl.Node node, List<TextSpan> out) {
      if (node.value != null) {
        out.add(TextSpan(text: node.value, style: styleFor(node.className)));
      } else if (node.children != null) {
        final children = <TextSpan>[];
        for (final c in node.children!) {
          walk(c, children);
        }
        out.add(TextSpan(children: children, style: styleFor(node.className)));
      }
    }

    for (final n in nodes) {
      walk(n, spans);
    }
    return TextSpan(
      children: spans,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    );
  }

  @override
  Widget build(BuildContext context) {
    final res = hl.highlight.parse(code, language: language);
    final nodes = res.nodes ?? const <hl.Node>[];
    final span = _buildSpan(nodes);
    return SelectableText.rich(span);
  }
}

class _InlineCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (element.tag == 'code') {
      final text = element.textContent;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );
    }
    return null;
  }
}
