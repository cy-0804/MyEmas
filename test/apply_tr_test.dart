import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apply .tr()', () async {
    final dir = Directory('lib');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in files) {
      String content = await file.readAsString();
      bool changed = false;

      // 1. Wrap Text('xyz') -> Text('xyz'.tr())
      final RegExp textRegExp = RegExp(r"Text\(\s*'([^'\$\\]+)'\s*\)");
      content = content.replaceAllMapped(textRegExp, (match) {
        final str = match.group(1)!;
        if (str.length < 2) return match.group(0)!; // ignore single chars
        changed = true;
        return "Text('$str'.tr())";
      });

      // 2. Wrap Text("xyz") -> Text("xyz".tr())
      final RegExp textRegExpDouble = RegExp(r'Text\(\s*"([^"\$\\]+)"\s*\)');
      content = content.replaceAllMapped(textRegExpDouble, (match) {
        final str = match.group(1)!;
        if (str.length < 2) return match.group(0)!; // ignore single chars
        changed = true;
        return 'Text("$str".tr())';
      });

      // 3. Wrap labelText: 'xyz' -> labelText: 'xyz'.tr()
      final RegExp labelRegExp = RegExp(
        r"(labelText|hintText|helperText|prefixText|suffixText|counterText|tooltip)\s*:\s*'([^'\$\\]+)'(?!\.tr\(\))",
      );
      content = content.replaceAllMapped(labelRegExp, (match) {
        final prop = match.group(1)!;
        final str = match.group(2)!;
        if (str.length < 2) return match.group(0)!;
        changed = true;
        return "$prop: '$str'.tr()";
      });

      final RegExp labelRegExpDouble = RegExp(
        r'(labelText|hintText|helperText|prefixText|suffixText|counterText|tooltip)\s*:\s*"([^"\$\\]+)"(?!\.tr\(\))',
      );
      content = content.replaceAllMapped(labelRegExpDouble, (match) {
        final prop = match.group(1)!;
        final str = match.group(2)!;
        if (str.length < 2) return match.group(0)!;
        changed = true;
        return '$prop: "$str".tr()';
      });

      // 4. Wrap SnackBar(content: Text('...'))
      final RegExp snackRegExp = RegExp(
        r"SnackBar\(\s*content\s*:\s*Text\(\s*'([^'\$\\]+)'\s*\)\s*\)",
      );
      content = content.replaceAllMapped(snackRegExp, (match) {
        final str = match.group(1)!;
        changed = true;
        return "SnackBar(content: Text('$str'.tr()))";
      });

      // Remove const keywords before widgets that we just made dynamic
      if (changed) {
        content = content.replaceAll(RegExp(r"const Text\("), "Text(");
        content = content.replaceAll(RegExp(r"const Row\("), "Row(");
        content = content.replaceAll(RegExp(r"const Center\("), "Center(");
        content = content.replaceAll(RegExp(r"const Column\("), "Column(");
        content = content.replaceAll(
          RegExp(r"const InputDecoration\("),
          "InputDecoration(",
        );
      }

      // 5. Add easy_localization import if changed and missing
      if (changed && !content.contains('easy_localization.dart')) {
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

      if (changed) {
        await file.writeAsString(content);
        print("Updated ${file.path}");
      }
    }
  });
}
