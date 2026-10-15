import 'package:flutter/material.dart';
import 'line_historical_monthly_import_page.dart';

/// New history starts with a file, not an unrelated SKO conversation picker.
class LineSourceUploadPage extends StatelessWidget {
  const LineSourceUploadPage({super.key});
  @override
  Widget build(BuildContext context) => const LineHistoricalMonthlyImportPage.newFile();
}
