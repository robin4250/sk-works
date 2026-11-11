import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

// Preserve the application asset path and bundle behavior exactly.
Future<ByteData> load(String path) => rootBundle.load(path);
Future<String> loadString(String path) => rootBundle.loadString(path);
