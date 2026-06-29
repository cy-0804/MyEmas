import 'dart:io';

void main() async {
  final files = [
    'lib/medication_dashboard_view.dart',
    'lib/sign_up_screen.dart',
    'lib/biometric_prompt_screen.dart',
    'lib/basic_info_screen.dart',
    'lib/caregiver_basic_info_screen.dart',
    'lib/add_edit_schedule_screen.dart',
    'lib/sos_notification_service.dart',
    'lib/caregiver_elderly_detail_screen.dart',
    'lib/health_info_intro_screen.dart',
    'lib/caregiver_qr_screen.dart'
  ];

  for (final filePath in files) {
    final file = File(filePath);
    if (!await file.exists()) continue;
    String content = await file.readAsString();
    
    content = content.replaceAll('const SnackBar(', 'SnackBar(');
    content = content.replaceAll('const SizedBox(', 'SizedBox(');
    content = content.replaceAll('const Text(', 'Text(');
    content = content.replaceAll('const Padding(', 'Padding(');
    content = content.replaceAll('const DropdownMenuItem(', 'DropdownMenuItem(');
    content = content.replaceAll('const Center(', 'Center(');
    content = content.replaceAll('const Column(', 'Column(');
    content = content.replaceAll('const Row(', 'Row(');
    content = content.replaceAll('const AlertDialog(', 'AlertDialog(');
    content = content.replaceAll('const Expanded(', 'Expanded(');
    content = content.replaceAll('const SingleChildScrollView(', 'SingleChildScrollView(');
    content = content.replaceAll('const Align(', 'Align(');
    content = content.replaceAll('const Positioned(', 'Positioned(');
    content = content.replaceAll('const Container(', 'Container(');
    content = content.replaceAll('children: const [', 'children: [');
    content = content.replaceAll('const [', '['); 
    
    await file.writeAsString(content);
    print('Fixed consts in $filePath');
  }
}
