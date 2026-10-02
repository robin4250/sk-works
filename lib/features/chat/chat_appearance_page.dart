import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatAppearance {
  const ChatAppearance({
    this.wallpaperPath,
    this.backgroundOpacity = 100,
    this.headerOpacity = 80,
    this.footerOpacity = 80,
    this.bubbleOpacity = 80,
  });

  final String? wallpaperPath;
  final int backgroundOpacity;
  final int headerOpacity;
  final int footerOpacity;
  final int bubbleOpacity;

  double get backgroundAlpha => backgroundOpacity / 100;
  double get headerAlpha => headerOpacity / 100;
  double get footerAlpha => footerOpacity / 100;
  double get bubbleAlpha => bubbleOpacity / 100;
}

class ChatAppearanceStore {
  const ChatAppearanceStore._();

  static String _key(String groupId, String name) =>
      'sko_chat_appearance_${groupId}_$name';

  static Future<ChatAppearance> load(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return ChatAppearance(
      wallpaperPath: prefs.getString(_key(groupId, 'wallpaper')),
      backgroundOpacity:
          (prefs.getInt(_key(groupId, 'background')) ?? 100).clamp(1, 100),
      headerOpacity:
          (prefs.getInt(_key(groupId, 'header')) ?? 80).clamp(1, 100),
      footerOpacity:
          (prefs.getInt(_key(groupId, 'footer')) ?? 80).clamp(1, 100),
      bubbleOpacity:
          (prefs.getInt(_key(groupId, 'bubble')) ?? 80).clamp(1, 100),
    );
  }

  static Future<void> save(String groupId, ChatAppearance value) async {
    final prefs = await SharedPreferences.getInstance();
    final wallpaper = value.wallpaperPath;
    if (wallpaper == null || wallpaper.isEmpty) {
      await prefs.remove(_key(groupId, 'wallpaper'));
    } else {
      await prefs.setString(_key(groupId, 'wallpaper'), wallpaper);
    }
    await prefs.setInt(_key(groupId, 'background'), value.backgroundOpacity);
    await prefs.setInt(_key(groupId, 'header'), value.headerOpacity);
    await prefs.setInt(_key(groupId, 'footer'), value.footerOpacity);
    await prefs.setInt(_key(groupId, 'bubble'), value.bubbleOpacity);
  }
}

class ChatAppearancePage extends StatefulWidget {
  const ChatAppearancePage({
    super.key,
    required this.groupId,
    required this.initial,
  });

  final String groupId;
  final ChatAppearance initial;

  @override
  State<ChatAppearancePage> createState() => _ChatAppearancePageState();
}

class _ChatAppearancePageState extends State<ChatAppearancePage> {
  final _picker = ImagePicker();
  late String? _wallpaperPath;
  late int _backgroundOpacity;
  late int _headerOpacity;
  late int _footerOpacity;
  late int _bubbleOpacity;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _wallpaperPath = widget.initial.wallpaperPath;
    _backgroundOpacity = widget.initial.backgroundOpacity;
    _headerOpacity = widget.initial.headerOpacity;
    _footerOpacity = widget.initial.footerOpacity;
    _bubbleOpacity = widget.initial.bubbleOpacity;
  }

  Future<void> _pickWallpaper() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final root = await getApplicationDocumentsDirectory();
      final folder = Directory('${root.path}/chat_wallpapers');
      if (!await folder.exists()) await folder.create(recursive: true);
      final destination = File('${folder.path}/${widget.groupId}.jpg');
      await File(picked.path).copy(destination.path);
      if (!mounted) return;
      setState(() => _wallpaperPath = destination.path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final value = ChatAppearance(
      wallpaperPath: _wallpaperPath,
      backgroundOpacity: _backgroundOpacity.clamp(1, 100),
      headerOpacity: _headerOpacity.clamp(1, 100),
      footerOpacity: _footerOpacity.clamp(1, 100),
      bubbleOpacity: _bubbleOpacity.clamp(1, 100),
    );
    await ChatAppearanceStore.save(widget.groupId, value);
    if (!mounted) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'チャット背景・透明度',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'このチャットだけの個人設定です。他のユーザーには反映されません。',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _wallpaperPath == null
                    ? const Center(child: Text('壁紙なし'))
                    : Image.file(
                        File(_wallpaperPath!),
                        fit: BoxFit.cover,
                        opacity: AlwaysStoppedAnimation(
                          _backgroundOpacity / 100,
                        ),
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Text('壁紙を読み込めません')),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _pickWallpaper,
              icon: const Icon(Icons.wallpaper_outlined),
              label: const Text('壁紙を選ぶ'),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() => _wallpaperPath = null),
              icon: const Icon(Icons.hide_image_outlined),
              label: const Text('壁紙を解除'),
            ),
            const Divider(height: 28),
            _slider(
              '壁紙の透明度',
              _backgroundOpacity,
              (value) => setState(() => _backgroundOpacity = value),
            ),
            _slider(
              'ヘッダー・タブの透明度',
              _headerOpacity,
              (value) => setState(() => _headerOpacity = value),
            ),
            _slider(
              'フッターの透明度',
              _footerOpacity,
              (value) => setState(() => _footerOpacity = value),
            ),
            _slider(
              'メッセージ背景の透明度',
              _bubbleOpacity,
              (value) => setState(() => _bubbleOpacity = value),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('このチャットに保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label  $value％',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        Slider(
          min: 1,
          max: 100,
          divisions: 99,
          value: value.toDouble(),
          label: '$value％',
          onChanged: (next) => onChanged(next.round().clamp(1, 100)),
        ),
      ],
    );
  }
}
