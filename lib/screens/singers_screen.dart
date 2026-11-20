import '../services/app_state.dart';
import '../utils/helpers.dart';
import '../widgets/mini_player.dart';
import '../widgets/ui.dart';
import 'package:flutter/material.dart';
import 'singer_form.dart';
import 'singer_page.dart';

class SingersScreen extends StatefulWidget {
  const SingersScreen({super.key});
  @override
  State<SingersScreen> createState() => _SingersScreenState();
}

class _SingersScreenState extends State<SingersScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final list = app.singers.where((s) => s.name.toLowerCase().contains(q.trim().toLowerCase())).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          return Scaffold(
            appBar: AppBar(title: const Text('זמרים')),
            floatingActionButton: FloatingActionButton(
                onPressed: () => go(context, const SingerForm()), child: const Icon(Icons.person_add_alt_1_rounded)),
            bottomNavigationBar: const WithMiniPlayer(),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SearchField(hint: 'חיפוש לפי שם', onChanged: (v) => setState(() => q = v)),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.mic_none_rounded,
                        title: app.singers.isEmpty ? 'עדיין אין זמרים' : 'לא נמצאו זמרים',
                        action: app.singers.isEmpty
                            ? FilledButton.tonal(onPressed: () => go(context, const SingerForm()), child: const Text('הוספת זמר'))
                            : null,
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: .82,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final s = list[i];
                          final count = app.songs.where((x) => x.singerId == s.id).length;
                          return Card(
                            child: InkWell(
                              onTap: () => go(context, SingerPage(s)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: IconButton(
                                      tooltip: 'מחיקת הזמר',
                                      icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                                      onPressed: () async {
                                        if (await confirm(context, 'למחוק את ${s.name} ואת כל השירים שלו?')) {
                                          app.deleteSinger(s);
                                        }
                                      },
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle, border: Border.all(color: Color(s.color), width: 2.5)),
                                    child: avatar(s, r: 38),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(s.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                  Text('$count שירים',
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          );
        },
      );
}
