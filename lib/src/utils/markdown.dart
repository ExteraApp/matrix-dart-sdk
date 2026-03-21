/*
 *   Famedly Matrix SDK
 *   Copyright (C) 2020, 2021 Famedly GmbH
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Affero General Public License as
 *   published by the Free Software Foundation, either version 3 of the
 *   License, or (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *   GNU Affero General Public License for more details.
 *
 *   You should have received a copy of the GNU Affero General Public License
 *   along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:convert';

import 'package:markdown/markdown.dart';

import 'package:matrix/src/utils/matrix_id_string_extension.dart';

const htmlAttrEscape = HtmlEscape(HtmlEscapeMode.attribute);

class SpoilerSyntax extends DelimiterSyntax {
  SpoilerSyntax()
      : super(
          r'\|\|',
          requiresDelimiterRun: true,
          tags: [DelimiterTag('span', 2)],
        );

  @override
  Iterable<Node>? close(
    InlineParser parser,
    Delimiter opener,
    Delimiter closer, {
    required String tag,
    required List<Node> Function() getChildren,
  }) {
    final children = getChildren();
    final newChildren = <Node>[];
    var searchingForReason = true;
    var reason = '';
    for (final child in children) {
      // If we already found a reason, let's just use our child nodes as-is
      if (!searchingForReason) {
        newChildren.add(child);
        continue;
      }
      if (child is Text) {
        final ix = child.text.indexOf('|');
        if (ix > 0) {
          reason += child.text.substring(0, ix);
          newChildren.add(Text(child.text.substring(ix + 1)));
          searchingForReason = false;
        } else {
          reason += child.text;
        }
      } else {
        // if we don't have a text node as reason we just want to cancel this whole thing
        break;
      }
    }
    // if we were still searching for a reason that means there was none - use the original children!
    final element =
        Element('span', searchingForReason ? children : newChildren);
    element.attributes['data-mx-spoiler'] =
        searchingForReason ? '' : htmlAttrEscape.convert(reason);
    return <Node>[element];
  }
}

class EmoteSyntax extends InlineSyntax {
  final Map<String, Map<String, String>> Function()? getEmotePacks;
  Map<String, Map<String, String>>? emotePacks;
  EmoteSyntax(this.getEmotePacks) : super(r':(?:([-\w]+)~)?([-\w]+):');

  @override
  bool onMatch(InlineParser parser, Match match) {
    final emotePacks = this.emotePacks ??= getEmotePacks?.call() ?? {};
    final pack = match[1] ?? '';
    final emote = match[2];
    String? mxc;
    if (pack.isEmpty) {
      // search all packs
      for (final emotePack in emotePacks.values) {
        mxc = emotePack[emote];
        if (mxc != null) {
          break;
        }
      }
    } else {
      mxc = emotePacks[pack]?[emote];
    }
    if (mxc == null) {
      // emote not found. Insert the whole thing as plain text
      parser.addNode(Text(match[0]!));
      return true;
    }
    final element = Element.empty('img');
    element.attributes['data-mx-emoticon'] = '';
    element.attributes['src'] = htmlAttrEscape.convert(mxc);
    element.attributes['alt'] = htmlAttrEscape.convert(':$emote:');
    element.attributes['title'] = htmlAttrEscape.convert(':$emote:');
    element.attributes['height'] = '32';
    element.attributes['vertical-align'] = 'middle';
    parser.addNode(element);
    return true;
  }
}

class InlineLatexSyntax extends DelimiterSyntax {
  InlineLatexSyntax() : super(r'\$([^\s$]([^\$]*[^\s$])?)\$');

  @override
  bool onMatch(InlineParser parser, Match match) {
    final element =
        Element('span', [Element.text('code', htmlEscape.convert(match[1]!))]);
    element.attributes['data-mx-maths'] = htmlAttrEscape.convert(match[1]!);
    parser.addNode(element);
    return true;
  }
}

// We also want to allow single-lines of like "$$latex$$"
class BlockLatexSyntax extends BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^[ ]{0,3}\$\$(.*)$');

  final endPattern = RegExp(r'^(.*)\$\$\s*$');

  @override
  List<Line?> parseChildLines(BlockParser parser) {
    final childLines = <Line>[];
    var first = true;
    while (!parser.isDone) {
      final match = endPattern.firstMatch(parser.current.content);
      if (match == null || (first && match[1]!.trim().isEmpty)) {
        childLines.add(parser.current);
        parser.advance();
      } else {
        childLines.add(Line(match[1]!));
        parser.advance();
        break;
      }
      first = false;
    }
    return childLines;
  }

  @override
  Node parse(BlockParser parser) {
    final childLines = parseChildLines(parser)
        .map((line) => line?.content)
        .whereType<String>();
    // we use .substring(2) as childLines will *always* contain the first two '$$'
    final latex = childLines.map((line) => line?.content).join('\n').trim().substring(2).trim();
    final element = Element('div', [
      Element('pre', [Element.text('code', htmlEscape.convert(latex))]),
    ]);
    element.attributes['data-mx-maths'] = htmlAttrEscape.convert(latex);
    return element;
  }
}

class PillSyntax extends InlineSyntax {
  PillSyntax()
      : super(
          r'([@#!][^\s:]*:(?:[^\s]+\.\w+|[\d\.]+|\[[a-fA-F0-9:]+\])(?::\d+)?)',
        );

  @override
  bool onMatch(InlineParser parser, Match match) {
    if (match.start > 0 &&
        !RegExp(r'[\s.!?:;\(]').hasMatch(match.input[match.start - 1])) {
      parser.addNode(Text(match[0]!));
      return true;
    }
    final identifier = match[1]!;
    final element = Element.text('a', htmlEscape.convert(identifier));
    element.attributes['href'] =
        htmlAttrEscape.convert(matrixUri(identifier));
    parser.addNode(element);
    return true;
  }
}

class MentionSyntax extends InlineSyntax {
  final String? Function(String)? getMention;
  MentionSyntax(this.getMention) : super(r'(@(?:\[[^\]:]+\]|\w+)(?:#\w+)?)');

  @override
  bool onMatch(InlineParser parser, Match match) {
    final mention = getMention?.call(match[1]!);
    if ((match.start > 0 &&
            !RegExp(r'[\s.!?:;\(]').hasMatch(match.input[match.start - 1])) ||
        mention == null) {
      parser.addNode(Text(match[0]!));
      return true;
    }
    final element = Element.text('a', htmlEscape.convert(match[1]!));
    element.attributes['href'] =
        htmlAttrEscape.convert(matrixUri(mention));
    parser.addNode(element);
    return true;
  }
}

String markdown(
  String text, {
  Map<String, Map<String, String>> Function()? getEmotePacks,
  String? Function(String)? getMention,
  bool convertLinebreaks = true,
}) {
  var ret = markdownToHtml(
    text
        // Escape HTML tags, but NOT inside inline/fenced code blocks:
        .escapeHtmlTagsOutsideCode()
        .replaceNewlines(),
    extensionSet: ExtensionSet.gitHubFlavored,
    blockSyntaxes: [
      BlockLatexSyntax(),
    ],
    inlineSyntaxes: [
      StrikethroughSyntax(),
      SpoilerSyntax(),
      EmoteSyntax(getEmotePacks),
      PillSyntax(),
      MentionSyntax(getMention),
      InlineLatexSyntax(),
    ],
  );

  var stripPTags = '<p>'.allMatches(ret).length <= 1;
  if (stripPTags) {
    const otherBlockTags = {
      'table',
      'pre',
      'ol',
      'ul',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'blockquote',
      'div',
    };
    for (final tag in otherBlockTags) {
      // we check for the close tag as the opening one might have attributes
      if (ret.contains('</$tag>')) {
        stripPTags = false;
        break;
      }
    }
  }
  ret = ret
      .trim()
      // Remove trailing linebreaks
      .replaceAll(RegExp(r'(<br />)+$'), '');
  if (convertLinebreaks) {
    // Only convert linebreaks which are not in <pre> blocks
    ret = ret.convertLinebreaksToBr('p');
    // Delete other linebreaks except for pre blocks:
    ret = ret.convertLinebreaksToBr('pre', exclude: true, replaceWith: '');
  }

  if (stripPTags) {
    ret = ret.replaceAll('<p>', '').replaceAll('</p>', '');
  }

  return ret;
}

extension on String {
  String escapeHtmlTagsOutsideCode() {
    final s = this;
    final out = StringBuffer();

    var i = 0;

    bool inInlineCode = false;
    String inlineDelim = '';

    bool inFencedCode = false;
    int fenceChar = 0; // '`' or '~' codeUnit
    int fenceLen = 0; // length of opening fence run

    bool isLineStart(int index) =>
        index == 0 || s.codeUnitAt(index - 1) == 0x0A; // '\n'

    bool isEscapedBacktick(int index) {
      // Treat ` as escaped if preceded by an odd number of backslashes.
      var bs = 0;
      var j = index - 1;
      while (j >= 0 && s.codeUnitAt(j) == 0x5C) {
        // '\'
        bs++;
        j--;
      }
      return bs.isOdd;
    }

    while (i < s.length) {
      if (!inInlineCode && !inFencedCode) {
        // Detect fenced code block start (``` or ~~~), up to 3 leading spaces.
        if (isLineStart(i)) {
          var j = i;
          var spaces = 0;
          while (j < s.length && spaces < 3 && s.codeUnitAt(j) == 0x20) {
            j++;
            spaces++;
          }

          if (j < s.length) {
            final ch = s.codeUnitAt(j);
            if (ch == 0x60 || ch == 0x7E) {
              // '`' or '~'
              var k = j;
              while (k < s.length && s.codeUnitAt(k) == ch) {
                k++;
              }
              final runLen = k - j;
              if (runLen >= 3) {
                inFencedCode = true;
                fenceChar = ch;
                fenceLen = runLen;

                // Copy the whole opening fence line as-is
                final lineEnd = s.indexOf('\n', k);
                if (lineEnd == -1) {
                  out.write(s.substring(i));
                  break;
                }
                out.write(s.substring(i, lineEnd + 1));
                i = lineEnd + 1;
                continue;
              }
            }
          }
        }

        // Detect inline code start (one or more backticks), not escaped.
        if (s.codeUnitAt(i) == 0x60 && !isEscapedBacktick(i)) {
          // '`'
          var j = i;
          while (j < s.length && s.codeUnitAt(j) == 0x60) {
            j++;
          }
          inlineDelim = s.substring(i, j);
          inInlineCode = true;
          out.write(inlineDelim);
          i = j;
          continue;
        }

        // Escape <...> outside code (same behavior as your old RegExp).
        if (s.codeUnitAt(i) == 0x3C) {
          // '<'
          final gt = s.indexOf('>', i + 1);
          if (gt != -1) {
            out.write('&lt;');
            out.write(s.substring(i + 1, gt));
            out.write('&gt;');
            i = gt + 1;
            continue;
          }
        }

        out.writeCharCode(s.codeUnitAt(i));
        i++;
        continue;
      }

      if (inInlineCode) {
        // Copy as-is until we see the exact same backtick run.
        if (inlineDelim.isNotEmpty && s.startsWith(inlineDelim, i)) {
          out.write(inlineDelim);
          i += inlineDelim.length;
          inInlineCode = false;
          inlineDelim = '';
        } else {
          out.writeCharCode(s.codeUnitAt(i));
          i++;
        }
        continue;
      }

      // inFencedCode
      if (inFencedCode) {
        // Detect closing fence on a line start (up to 3 leading spaces),
        // with at least the opening fence length.
        if (isLineStart(i)) {
          var j = i;
          var spaces = 0;
          while (j < s.length && spaces < 3 && s.codeUnitAt(j) == 0x20) {
            j++;
            spaces++;
          }

          if (j < s.length && s.codeUnitAt(j) == fenceChar) {
            var k = j;
            while (k < s.length && s.codeUnitAt(k) == fenceChar) {
              k++;
            }
            if (k - j >= fenceLen) {
              final lineEnd = s.indexOf('\n', k);
              if (lineEnd == -1) {
                out.write(s.substring(i));
                break;
              }
              out.write(s.substring(i, lineEnd + 1));
              i = lineEnd + 1;

              inFencedCode = false;
              fenceChar = 0;
              fenceLen = 0;
              continue;
            }
          }
        }

        out.writeCharCode(s.codeUnitAt(i));
        i++;
      }
    }

    return out.toString();
  }

  String replaceNewlines() {
    // RegEx for at least 3 following \n
    final regExp = RegExp(r'(\n{3,})');

    return replaceAllMapped(regExp, (match) {
      final newLineGroup = match.group(0)!;
      return newLineGroup
          .replaceAll('\n', '<br/>')
          .replaceFirst('<br/><br/>', '\n\n');
    });
  }

  String convertLinebreaksToBr(
    String tagName, {
    bool exclude = false,
    String replaceWith = '<br/>',
  }) {
    final parts = split('$tagName>');
    var convertLinebreaks = exclude;
    for (var i = 0; i < parts.length; i++) {
      if (convertLinebreaks) parts[i] = parts[i].replaceAll('\n', replaceWith);
      convertLinebreaks = !convertLinebreaks;
    }
    return parts.join('$tagName>');
  }
}
