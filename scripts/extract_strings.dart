import 'dart:io';

void main() async {
  final dir = Directory('lib');
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  final Set<String> strings = {};

  for (final file in files) {
    final content = await file.readAsString();

    // 1. Text('xyz') or Text("xyz")
    final textRegExp = RegExp(
      r"Text\(\s*['"
      '"'
      r"]([^'\$\\]+)['"
      '"'
      r"]\s*(?:,|\))",
    );
    for (final match in textRegExp.allMatches(content)) {
      if (match.group(1)!.length > 1) strings.add(match.group(1)!);
    }

    // 2. labelText: 'xyz', hintText: 'xyz', title: 'xyz'
    final labelRegExp = RegExp(
      r"(labelText|hintText|title|subtitle|label)\s*:\s*['"
      '"'
      r"]([^'\$\\]+)['"
      '"'
      r"]",
    );
    for (final match in labelRegExp.allMatches(content)) {
      if (match.group(2)!.length > 1) strings.add(match.group(2)!);
    }

    // 3. 'xyz'.tr()
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
  }

  // filter out anything that is already in en.json
  final enJsonFile = File('assets/translations/en.json');
  final enJsonContent = await enJsonFile.readAsString();
  final enStrings = enJsonContent
      .split('\n')
      .map((l) {
        final match = RegExp(r'"([^"]+)"\s*:').firstMatch(l);
        return match?.group(1);
      })
      .whereType<String>()
      .toSet();

  final missing = strings.difference(enStrings);
  print('MISSING_STRINGS_START');
  for (final s in missing) {
    print(s);
  }
  print('MISSING_STRINGS_END');
}
