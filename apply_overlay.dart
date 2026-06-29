import 'dart:io';

void main() {
  final file = File('lib/medication_dashboard_view.dart');
  var code = file.readAsStringSync();

  final helper = '''
Future<void> _triggerNotificationAndOverlay(
  int id,
  String title,
  String body,
  String payload,
) async {
  // Show standard notification
  await _notifPlugin.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'medication_channel',
        'Medication Reminders',
        channelDescription: 'Reminds you to take your medication',
        importance: Importance.max,
        priority: Priority.max,
      ),
      iOS: DarwinNotificationDetails(),
    ),
    payload: payload,
  );

  // Show system overlay window
  try {
    final isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (isGranted) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        flag: OverlayFlag.defaultFlag,
        alignment: OverlayAlignment.center,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: 400,
        width: OverlayWindowSize.matchParent,
      );
      await FlutterOverlayWindow.shareData({
        'title': title,
        'body': body,
      });
    }
  } catch (e) {
    debugPrint('Overlay error: \$e');
  }
}
''';

  code = code.replaceFirst(
    'void _showDialogWhenReady(',
    '$helper\nvoid _showDialogWhenReady(',
  );

  final rep1 = '''      await _notifPlugin.show(
        medId.hashCode,
        '💊 Time to take \${med.name}!',
        '\${med.dosage ?? ""} — \${med.instruction ?? "as directed"}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_channel',
            'Medication Reminders',
            channelDescription: 'Reminds you to take your medication',
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );''';

  final new1 = '''      await _triggerNotificationAndOverlay(
        medId.hashCode,
        '💊 Time to take \${med.name}!',
        '\${med.dosage ?? ""} — \${med.instruction ?? "as directed"}',
        payload,
      );''';

  final rep2 = '''      await _notifPlugin.show(
        medId.hashCode,
        '⚠️ Missed Medication: \${med.name}',
        'Please remember to take your medication.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_channel',
            'Medication Reminders',
            channelDescription: 'Reminds you to take your medication',
            importance: Importance.max,
            priority: Priority.max,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );''';

  final new2 = '''      await _triggerNotificationAndOverlay(
        medId.hashCode,
        '⚠️ Missed Medication: \${med.name}',
        'Please remember to take your medication.',
        payload,
      );''';

  final rep3 = '''                await _notifPlugin.show(
                  medId.hashCode,
                  '🚨 FINAL REMINDER: \${med.name}',
                  'You have not taken your medication. This is the final reminder before your caregiver is alerted!',
                  const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'medication_channel',
                      'Medication Reminders',
                      channelDescription: 'Reminds you to take your medication',
                      importance: Importance.max,
                      priority: Priority.max,
                    ),
                    iOS: DarwinNotificationDetails(),
                  ),
                  payload: payload,
                );''';

  final new3 = '''                await _triggerNotificationAndOverlay(
                  medId.hashCode,
                  '🚨 FINAL REMINDER: \${med.name}',
                  'You have not taken your medication. This is the final reminder before your caregiver is alerted!',
                  payload,
                );''';

  final rep4 = '''                            await _notifPlugin.show(
                              medId.hashCode,
                              '⚠️ Low Stock Alert',
                              '\${med.name} has only \${stock.toInt()} left. Please restock soon.',
                              const NotificationDetails(
                                android: AndroidNotificationDetails(
                                  'medication_channel',
                                  'Medication Reminders',
                                  channelDescription:
                                      'Reminds you to take your medication',
                                  importance: Importance.max,
                                  priority: Priority.max,
                                ),
                                iOS: DarwinNotificationDetails(),
                              ),
                              payload: payload,
                            );''';

  final new4 =
      '''                            await _triggerNotificationAndOverlay(
                              medId.hashCode,
                              '⚠️ Low Stock Alert',
                              '\${med.name} has only \${stock.toInt()} left. Please restock soon.',
                              payload,
                            );''';

  final rep5 = '''  await _notifPlugin.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'medication_channel',
        'Medication Reminders',
        channelDescription: 'Reminds you to take your medication',
        importance: Importance.max,
        priority: Priority.max,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );''';

  final new5 = '''  await _triggerNotificationAndOverlay(
    id,
    title,
    body,
    '',
  );''';

  final rep6 = '''  const androidDetails = AndroidNotificationDetails(
    'medication_channel',
    'Medication Reminders',
    channelDescription: 'Reminds you to take your medication',
    importance: Importance.max,
    priority: Priority.max,
  );
  const iosDetails = DarwinNotificationDetails();
  const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

  await _notifPlugin.show(
    id,
    title,
    body,
    details,
  );''';

  code = code.replaceAll(rep1, new1);
  code = code.replaceAll(rep2, new2);
  code = code.replaceAll(rep3, new3);
  code = code.replaceAll(rep4, new4);
  code = code.replaceAll(rep5, new5);
  code = code.replaceAll(rep6, new5);

  file.writeAsStringSync(code);
  print("Done replacing");
}
