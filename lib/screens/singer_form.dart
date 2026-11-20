import '../services/file_service.dart';
import '../models/singer.dart';
import '../services/app_state.dart';
import '../utils/helpers.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class SingerForm extends StatefulWidget {
  final Singer? singer;
  const SingerForm({super.key, this.singer});
  @override
  State<SingerForm> createState() => _SingerFormState();
}

class _SingerFormState extends State<SingerForm> {
  late final name = TextEditingController(text: widget.singer?.name);
  late final notes = TextEditingController(text: widget.singer?.notes);
  late int color = widget.singer?.color ?? Colors.primaries[0].toARGB32();
  String? image;
  Uint8List? imageBytes;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    image = widget.singer?.image;
  }

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final f = await pickMedia(FileType.image, needBytes: true);
    if (f == null || f.bytes == null) return;
    final Uint8List bytes = f.bytes!;
    setState(() {
      imageBytes = bytes;
      uploading = app.githubReady;
    });
    try {
      final remotePath =
          app.githubReady ? await app.uploadMediaBytes(fileName: f.name, bytes: bytes, folder: 'singers') : null;
      setState(() {
        image = remotePath == null
            ? 'data:image/${f.name.toLowerCase().endsWith('png') ? 'png' : 'jpeg'};base64,${base64Encode(bytes)}'
            : app.githubRawUrl(remotePath);
      });
    } catch (e) {
      if (mounted) snack(context, 'העלאת התמונה נכשלה: $e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  void submit() {
    if (name.text.trim().isEmpty) {
      snack(context, 'יש להזין שם');
      return;
    }
    final s = widget.singer;
    if (s == null) {
      app.singers.add(Singer(id: app.newId(), name: name.text.trim(), notes: notes.text, image: image, color: color));
    } else {
      s
        ..name = name.text.trim()
        ..notes = notes.text
        ..image = image
        ..color = color;
    }
    app.save();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.singer == null ? 'זמר חדש' : 'עריכת זמר'), actions: [
          if (widget.singer != null)
            IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (await confirm(context, 'למחוק את הזמר וכל השירים שלו?')) {
                    app.deleteSinger(widget.singer!);
                    if (context.mounted) {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    }
                  }
                }),
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: GestureDetector(
              onTap: uploading ? null : pickImage,
              child: Stack(alignment: Alignment.bottomLeft, children: [
                imageBytes != null
                    ? CircleAvatar(radius: 56, backgroundImage: MemoryImage(imageBytes!))
                    : avatar(Singer(id: '', name: name.text, image: image, color: color), r: 56),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: uploading
                      ? SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                      : Icon(Icons.photo_camera_rounded, size: 18, color: Theme.of(context).colorScheme.onPrimary),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: name,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'שם הזמר', prefixIcon: Icon(Icons.mic_rounded)),
          ),
          const SizedBox(height: 16),
          Text('צבע לזיהוי', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: Colors.primaries
                .map((c) => GestureDetector(
                      onTap: () => setState(() => color = c.toARGB32()),
                      child: CircleAvatar(
                        backgroundColor: c,
                        radius: 17,
                        child: color == c.toARGB32() ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'הערות', alignLabelWithHint: true)),
          const SizedBox(height: 20),
          FilledButton(onPressed: uploading ? null : submit, child: const Text('שמירה')),
        ]),
      );
}
