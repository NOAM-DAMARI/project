import '../services/app_state.dart';
import '../services/export_service.dart';
import '../services/storage.dart';
import '../utils/helpers.dart';
import '../widgets/ui.dart';
import 'offline_models_screen.dart';
import '../widgets/transcription_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class SettingsScreen extends StatefulWidget {
  /// נפתח ממסך אחר (עם כפתור חזרה)
  final bool standalone;
  const SettingsScreen({super.key, this.standalone = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final owner = TextEditingController(text: app.githubOwner);
  late final repo = TextEditingController(text: app.githubRepo);
  late final branch = TextEditingController(text: app.githubBranch);
  late final token = TextEditingController(text: app.githubToken);

  bool showToken = false;
  bool busy = false;
  int cacheBytes = cacheSizeBytes();

  @override
  void dispose() {
    for (final c in [owner, repo, branch, token]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> connect() async {
    if (owner.text.trim().isEmpty ||
        repo.text.trim().isEmpty ||
        token.text.trim().isEmpty) {
      snack(context, 'יש למלא בעלים, מאגר ו-Token');
      return;
    }
    setState(() => busy = true);
    await app.configureGitHub(
        owner: owner.text,
        repo: repo.text,
        branch: branch.text,
        token: token.text);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _runRepositoryAction(
      Future<void> Function() action, String successMessage) async {
    setState(() => busy = true);
    try {
      await action();
      if (mounted) snack(context, successMessage);
    } catch (error) {
      if (mounted) snack(context, 'הפעולה נכשלה: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final c = Theme.of(context).colorScheme;
          final activeStorage = [
            if (app.githubReady)
              'GitHub · ${app.githubOwner}/${app.githubRepo}',
            if (app.localEnabled) 'תיקייה מקומית',
          ];
          final storageActive = activeStorage.isNotEmpty;
          return Scaffold(
            appBar: AppBar(
                title: const Text('הגדרות'),
                automaticallyImplyLeading: widget.standalone),
            body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  SettingsCard(
                      title: 'מראה',
                      icon: Icons.palette_outlined,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('מצב כהה'),
                          value: app.dark,
                          onChanged: app.setDark,
                        ),
                      ]),

                  // ---------- מקור אחסון ----------
                  SettingsCard(
                      title: 'מקור אחסון',
                      icon: Icons.storage_rounded,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: const {'github', 'local', 'both'}
                                  .contains(app.storageMode)
                              ? app.storageMode
                              : 'github',
                          decoration: const InputDecoration(
                              labelText: 'בחר מקור אחסון'),
                          items: const [
                            DropdownMenuItem(
                                value: 'github', child: Text('GitHub')),
                            DropdownMenuItem(
                                value: 'local', child: Text('תיקייה מקומית')),
                            DropdownMenuItem(
                                value: 'both',
                                child: Text('GitHub + תיקייה מקומית')),
                          ],
                          onChanged: (mode) async {
                            if (mode == null) return;
                            if (mode != 'github' && app.localFolder.isEmpty) {
                              snack(context,
                                  'בחר תיקייה מקומית בכרטיס "תיקייה במחשב" למטה');
                            }
                            await app.setStorageMode(mode);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'החלפת מקור לא מוחקת את ה-Token של GitHub, את שם המאגר או נתונים קיימים.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: c.onSurfaceVariant),
                        ),
                      ]),

                  // ---------- GitHub ----------
                  SettingsCard(
                      title: 'מצב סנכרון',
                      icon: Icons.cloud_sync_outlined,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (storageActive
                                    ? c.primaryContainer
                                    : c.surfaceContainerHighest)
                                .withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            Icon(
                                storageActive
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_off_rounded,
                                color: storageActive
                                    ? c.primary
                                    : c.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        storageActive
                                            ? 'מחובר: ${activeStorage.join(' + ')}'
                                            : 'לא מחובר',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    Text(app.syncMessage,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                    if (app.lastSync != null)
                                      Text(
                                          'סנכרון אחרון: ${TimeOfDay.fromDateTime(app.lastSync!).format(context)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                  ]),
                            ),
                            if (app.syncing)
                              const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: owner,
                                  decoration: const InputDecoration(
                                      labelText: 'משתמש / בעלים'))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: TextField(
                                  controller: repo,
                                  decoration: const InputDecoration(
                                      labelText: 'שם המאגר'))),
                        ]),
                        const SizedBox(height: 10),
                        TextField(
                            controller: branch,
                            decoration:
                                const InputDecoration(labelText: 'Branch')),
                        const SizedBox(height: 10),
                        TextField(
                          controller: token,
                          obscureText: !showToken,
                          decoration: InputDecoration(
                            labelText: 'GitHub Personal Access Token',
                            suffixIcon: IconButton(
                              icon: Icon(showToken
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded),
                              onPressed: () =>
                                  setState(() => showToken = !showToken),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: busy ? null : connect,
                          icon: const Icon(Icons.link_rounded),
                          label: Text(busy ? 'מתחבר...' : 'חבר מאגר'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: app.githubReady && !app.syncing && !busy
                              ? () async {
                                  if (!await confirm(
                                      context,
                                      'הייבוא יחליף את הנתונים המקומיים בנתוני המאגר. להמשיך?',
                                      ok: 'ייבא')) return;
                                  await _runRepositoryAction(
                                      app.importFromGitHub,
                                      'הנתונים יובאו מהמאגר');
                                }
                              : null,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('ייבא מהמאגר'),
                        ),
                        OutlinedButton.icon(
                          onPressed: storageActive && !app.syncing && !busy
                              ? () => _runRepositoryAction(
                                  app.syncMissingData,
                                  'הסנכרון הושלם: הנתונים החסרים מוזגו')
                              : null,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('סנכרן: שמור וייבא נתונים חסרים'),
                        ),
                        OutlinedButton.icon(
                          onPressed: app.githubReady && !app.syncing && !busy
                              ? () => _runRepositoryAction(
                                  app.uploadMissingToGitHub,
                                  'הועלו למאגר רק הנתונים שחסרו')
                              : null,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('העלה למאגר רק מה שחסר'),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: app.githubEnabled && !busy
                              ? app.disconnectGitHub
                              : null,
                          icon: const Icon(
                              Icons.pause_circle_outline_rounded),
                          label: const Text('השהיה (שומר פרטים)'),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.key_off_rounded),
                          label: const Text('מחיקת ה-Token מהמכשיר'),
                          onPressed: app.githubToken.isEmpty
                              ? null
                              : () async {
                                  if (!await confirm(
                                      context, 'למחוק את ה-Token מהמכשיר?',
                                      ok: 'מחיקה')) return;
                                  await app.forgetGitHubToken();
                                  token.clear();
                                },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'נדרשת הרשאת Contents: Read and write. '
                          'קבצי השמע נשמרים ב-GitHub Releases – עד 2GB לכל קובץ, בלי לנפח את המאגר. '
                          'ה-Token נשמר רק במכשיר הזה. אין להפיץ Token אישי בתוך APK או אתר ציבורי.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: c.onSurfaceVariant),
                        ),
                      ]),

                  SettingsCard(
                      title: 'תיקייה במחשב',
                      icon: Icons.folder_outlined,
                      children: [
                        Text(app.localFolder.isNotEmpty
                            ? '${app.localEnabled ? 'פעילה' : 'שמורה (לא פעילה במצב GitHub)'}: ${app.localFolder}'
                            : 'לא נבחרה תיקייה מקומית'),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton.icon(
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('בחירת תיקייה'),
                            onPressed: () async {
                              if (kIsWeb) {
                                snack(context,
                                    'בדפדפן אין גישה לתיקיות במחשב. חיבור תיקייה זמין באפליקציה ל-Windows / Mac / Linux / אנדרואיד.');
                                return;
                              }
                              String? path;
                              try {
                                path = await FilePicker.platform
                                    .getDirectoryPath(
                                        dialogTitle: 'בחר תיקיית סנכרון');
                              } catch (e) {
                                debugPrint('directory picker failed: $e');
                              }
                              if (!context.mounted) return;
                              // גיבוי: אם סייר הקבצים לא נפתח/לא החזיר נתיב – הקלדה ידנית
                              path ??= await askText(context,
                                  'נתיב התיקייה (למשל C:\\MusicManager או /storage/emulated/0/MusicManager)',
                                  init: app.localFolder);
                              if (path == null ||
                                  path.trim().isEmpty ||
                                  !context.mounted) return;
                              try {
                                await app.configureLocalFolder(path);
                                if (context.mounted) {
                                  snack(
                                      context,
                                      app.githubReady
                                          ? 'התיקייה מחוברת. שינויים יישמרו גם ב-GitHub וגם בתיקייה (בלי לדרוס את הגדרות GitHub).'
                                          : 'התיקייה חוברה – הנתונים והקבצים יישמרו בה');
                                }
                              } catch (e) {
                                if (context.mounted)
                                  snack(context,
                                      'אין הרשאת כתיבה לתיקייה הזו. בחר תיקייה אחרת (למשל Documents). $e');
                              }
                            },
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                              child: OutlinedButton.icon(
                            icon: const Icon(Icons.link_off_rounded),
                            label: const Text('ניתוק'),
                            onPressed: app.localEnabled
                                ? app.disconnectLocalFolder
                                : null,
                          )),
                        ]),
                        const SizedBox(height: 6),
                        Text(
                            'החיבור ל-GitHub נשמר בנפרד. במצב "גם וגם" הנתונים נשמרים בשניהם.',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (app.localEnabled) ...[
                          const Divider(height: 24),
                          Text(
                              'להעלאת קבצים או לייבוא סלקטיבי מתוך ZIP, פתח את מסך ״קבצים״.',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ]),

                  if (!kIsWeb)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.offline_bolt_outlined),
                        title: const Text('תמלול מקומי (ללא אינטרנט)'),
                        subtitle: const Text(
                            'הורדת מודל: מהיר 190MB · מומלץ 574MB · עברית 1.6GB'),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => go(context, const OfflineModelsScreen()),
                      ),
                    ),

                  // ---------- תמלול ----------
                  SettingsCard(
                    title: 'תמלול אוטומטי',
                    icon: Icons.auto_awesome_outlined,
                    children: const [TranscriptionSettings()],
                  ),

                  // ---------- אחסון ----------
                  SettingsCard(
                      title: 'האזנה ללא אינטרנט',
                      icon: Icons.download_for_offline_outlined,
                      children: [
                        Text(
                            'קבצים שהורדו מהענן נשמרים במכשיר להאזנה ללא אינטרנט. תפוס כרגע: ${fmtBytes(cacheBytes)}'),
                        // הכפתור מוצג רק כשיש קבצים לפינוי
                        if (cacheBytes > 0) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.cleaning_services_outlined),
                            label: const Text('פינוי מקום'),
                            onPressed: () async {
                              if (!await confirm(context,
                                  'למחוק את הקבצים השמורים? הם יורדו שוב בעת האזנה.',
                                  ok: 'פינוי')) return;
                              await clearCache();
                              setState(() => cacheBytes = cacheSizeBytes());
                            },
                          ),
                        ],
                      ]),

                  SettingsCard(
                      title: 'גיבוי ושחזור (כולל מועדפים)',
                      icon: Icons.backup_outlined,
                      children: backupTiles(context)),
                ]),
          );
        },
      );
}
