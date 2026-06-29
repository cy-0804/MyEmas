import os
import re
import json

def process_file(filepath, strings_set):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Regex to find Text('something') or Text("something")
    # We ignore strings that have '$' (interpolation)
    pattern1 = re.compile(r"Text\(\s*'([^'\$]+)'\s*([,\)])")
    pattern2 = re.compile(r'Text\(\s*"([^"\$]+)"\s*([,\)])')
    
    def replacer(match):
        text = match.group(1)
        suffix = match.group(2)
        strings_set.add(text)
        # return Text('something'.tr())
        return f"Text('{text}'.tr()){suffix}"

    new_content = pattern1.sub(replacer, content)
    new_content = pattern2.sub(replacer, new_content)
    
    # Add import 'package:easy_localization/easy_localization.dart'; if changed
    if new_content != content:
        if "package:easy_localization/easy_localization.dart" not in new_content:
            # insert import at the top
            lines = new_content.split('\n')
            for i, line in enumerate(lines):
                if line.startswith('import '):
                    lines.insert(i, "import 'package:easy_localization/easy_localization.dart';")
                    break
            new_content = '\n'.join(lines)
            
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)

def main():
    lib_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'lib')
    strings_set = set()
    
    for root, dirs, files in os.walk(lib_dir):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                process_file(filepath, strings_set)
                
    print(f"Extracted {len(strings_set)} unique strings.")
    
    # Create translations dir
    trans_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'translations')
    os.makedirs(trans_dir, exist_ok=True)
    
    # en.json
    en_dict = {s: s for s in strings_set}
    with open(os.path.join(trans_dir, 'en.json'), 'w', encoding='utf-8') as f:
        json.dump(en_dict, f, indent=2, ensure_ascii=False)
        
    print("Done!")

if __name__ == '__main__':
    main()
