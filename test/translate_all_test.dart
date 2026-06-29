import 'dart:io';
import 'dart:convert';

void main() async {
  print('Starting comprehensive translation update...');
  final dir = Directory('lib');
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  final Set<String> strings = {};

  for (final file in files) {
    String content = await file.readAsString();
    bool changed = false;

    // 1. Text('xyz') -> Text('xyz'.tr())
    final textRegExp = RegExp(r"Text\(\s*'([^'\$\\]+)'\s*(?:,|\))");
    content = content.replaceAllMapped(textRegExp, (match) {
      final str = match.group(1)!;
      if (str.length < 2) return match.group(0)!;
      strings.add(str);
      changed = true;
      return match.group(0)!.replaceFirst("'$str'", "'$str'.tr()");
    });

    final textRegExpDouble = RegExp(r'Text\(\s*"([^"\$\\]+)"\s*(?:,|\))');
    content = content.replaceAllMapped(textRegExpDouble, (match) {
      final str = match.group(1)!;
      if (str.length < 2) return match.group(0)!;
      strings.add(str);
      changed = true;
      return match.group(0)!.replaceFirst('"$str"', '"$str".tr()');
    });

    // 2. labelText, hintText, title, subtitle, label
    final labelRegExp = RegExp(
      r"(labelText|hintText|title|subtitle|label)\s*:\s*'([^'\$\\]+)'(?!\.tr\(\))",
    );
    content = content.replaceAllMapped(labelRegExp, (match) {
      final prop = match.group(1)!;
      final str = match.group(2)!;
      if (str.length < 2) return match.group(0)!;
      strings.add(str);
      changed = true;
      return "$prop: '$str'.tr()";
    });

    // Extract existing .tr() calls
    final trRegExp = RegExp(
      r"['"
      '"'
      r"]([^'\$\\]+)['"
      '"'
      r"]\.tr\(\)",
    );
    for (final match in trRegExp.allMatches(content)) {
      if (match.group(1)!.length > 1) strings.add(match.group(1)!);
    }

    if (changed) {
      content = content.replaceAll(RegExp(r"const Text\("), "Text(");
      content = content.replaceAll(RegExp(r"const Row\("), "Row(");
      content = content.replaceAll(RegExp(r"const Center\("), "Center(");
      content = content.replaceAll(RegExp(r"const Column\("), "Column(");
      content = content.replaceAll(
        RegExp(r"const InputDecoration\("),
        "InputDecoration(",
      );

      if (!content.contains('easy_localization.dart')) {
        final importIndex = content.lastIndexOf(
          RegExp(r"^import\s+'.+';$", multiLine: true),
        );
        if (importIndex != -1) {
          final endOfLine = content.indexOf('\n', importIndex);
          content =
              "${content.substring(0, endOfLine + 1)}import 'package:easy_localization/easy_localization.dart';\n${content.substring(endOfLine + 1)}";
        } else {
          content =
              "import 'package:easy_localization/easy_localization.dart';\n$content";
        }
      }
      await file.writeAsString(content);
      print('Updated ${file.path}');
    }
  }

  // Update JSON files
  final languages = ['en', 'ms', 'zh'];
  for (final lang in languages) {
    final file = File('assets/translations/$lang.json');
    if (!await file.exists()) continue;

    final content = await file.readAsString();
    final Map<String, dynamic> jsonMap = jsonDecode(content);

    int added = 0;
    for (final s in strings) {
      if (!jsonMap.containsKey(s)) {
        jsonMap[s] = s; // fallback to english for missing translations
        added++;
      }
    }

    if (added > 0) {
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(jsonMap),
      );
      print('Added $added missing strings to $lang.json');
    }
  }

  print('Done! Hot restart your app.');
}
