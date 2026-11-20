
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../services/download_bytes.dart';
import '../utils/helpers.dart';

class PdfPreviewScreen extends StatelessWidget {
  final String title;
  final String fileName;
  final Future<Uint8List> Function() buildPdf;

  const PdfPreviewScreen({super.key, required this.title, required this.fileName, required this.buildPdf});

  Future<void> _print(BuildContext context) async {
    try {
      await Printing.layoutPdf(onLayout: (_) => buildPdf());
    } catch (error) {
      if (context.mounted) snack(context, 'ההדפסה נכשלה: $error');
    }
  }

  Future<void> _download(BuildContext context) async {
    try {
      final bytes = await buildPdf();
      if (kIsWeb) {
        await downloadBytes(bytes, fileName, 'application/pdf');
        return;
      }
      final path = await FilePicker.platform.saveFile(fileName: fileName, bytes: bytes);
      if (path == null && context.mounted) {
        snack(context, 'לא נבחר מיקום לשמירת הקובץ');
      } else if (context.mounted) {
        snack(context, 'הקובץ נשמר');
      }
    } catch (error) {
      if (context.mounted) snack(context, 'שמירת הקובץ נכשלה: $error');
    }
  }

  Future<void> _share(BuildContext context) async {
    try {
      await Printing.sharePdf(bytes: await buildPdf(), filename: fileName);
    } catch (error) {
      if (context.mounted) snack(context, 'השיתוף נכשל: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('תצוגת PDF · $title', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'הדפס', onPressed: () => _print(context), icon: const Icon(Icons.print_rounded)),
            IconButton(tooltip: 'הורד', onPressed: () => _download(context), icon: const Icon(Icons.download_rounded)),
            IconButton(tooltip: 'שתף', onPressed: () => _share(context), icon: const Icon(Icons.share_rounded)),
          ],
        ),
        body: PdfPreview(
          build: (_) => buildPdf(),
          pdfFileName: fileName,
          initialPageFormat: PdfPageFormat.a4,
          canChangePageFormat: false,
          canChangeOrientation: false,
          allowPrinting: false,
          allowSharing: false,
        ),
      );
}
