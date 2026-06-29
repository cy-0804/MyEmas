import 'dart:io';
import 'dart:convert';

void processFile(File file, Set<String> stringsSet) {
  String content = file.readAsStringSync();
  
  // Regex to find Text('something') or Text("something")
  // We ignore strings that have '$' (interpolation)
  final pattern1 = RegExp(r"Text\(\s*'([^'\$]+)'\s*([,\)])");
  final pattern2 = RegExp(r'Text\(\s*"([^"\$]+)"\s*([,\)])');
  
  String replacer(Match match) {
    String text = match.group(1)!;
    String suffix = match.group(2)!;
    stringsSet.add(text);
    return "Text('$text'.tr())$suffix";
  }

  String newContent = content.replaceAllMapped(pattern1, replacer);
  newContent = newContent.replaceAllMapped(pattern2, replacer);
  
  // Add import 'package:easy_localization/easy_localization.dart'; if changed
  if (newContent != content) {
    if (!newContent.contains("package:easy_localization/easy_localization.dart")) {
      List<String> lines = newContent.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('import ')) {
          lines.insert(i, "import 'package:easy_localization/easy_localization.dart';");
          break;
        }
      }
      newContent = lines.join('\n');
    }
    file.writeAsStringSync(newContent);
  }
}

void main() {
  final libDir = Directory('../lib');
  if (!libDir.existsSync()) {
    print('Run from scripts directory.');
    return;
  }
  
  final stringsSet = <String>{};
  
  final entities = libDir.listSync(recursive: true);
  for (var entity in entities) {
    if (entity is File && entity.path.endsWith('.dart')) {
      processFile(entity, stringsSet);
    }
  }
  
  print('Extracted ${stringsSet.length} unique strings.');
  
  final transDir = Directory('../assets/translations');
  if (!transDir.existsSync()) {
    transDir.createSync(recursive: true);
  }
  
  final enDict = { for (var s in stringsSet) s : s };
  
  final file = File('../assets/translations/en.json');
  file.writeAsStringSync(JsonEncoder.withIndent('  ').convert(enDict));
  
  print('Done! Wrote to assets/translations/en.json');
}
