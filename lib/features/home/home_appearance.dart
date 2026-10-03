import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/supabase_backend.dart';

class HomeAppearance {
  const HomeAppearance({
    this.wallpaperPath,
    this.wallpaperOpacity = 1,
    this.buttonOpacity = 0.8,
    this.cardButtonOpacity = 1,
    this.cardOpacity = 0.8,
    this.headerOpacity = 0.8,
    this.footerOpacity = 0.8,
  });

  final String? wallpaperPath;
  final double wallpaperOpacity;
  final double buttonOpacity;
  final double cardButtonOpacity;
  final double cardOpacity;
  final double headerOpacity;
  final double footerOpacity;

  static double normalize(double value) => value.clamp(0.01, 1.0);

  HomeAppearance copyWith({
    String? wallpaperPath,
    bool clearWallpaper = false,
    double? wallpaperOpacity,
    double? buttonOpacity,
    double? cardButtonOpacity,
    double? cardOpacity,
    double? headerOpacity,
    double? footerOpacity,
  }) {
    return HomeAppearance(
      wallpaperPath: clearWallpaper ? null : wallpaperPath ?? this.wallpaperPath,
      wallpaperOpacity: normalize(wallpaperOpacity ?? this.wallpaperOpacity),
      buttonOpacity: normalize(buttonOpacity ?? this.buttonOpacity),
      cardButtonOpacity:
          normalize(cardButtonOpacity ?? this.cardButtonOpacity),
      cardOpacity: normalize(cardOpacity ?? this.cardOpacity),
      headerOpacity: normalize(headerOpacity ?? this.headerOpacity),
      footerOpacity: normalize(footerOpacity ?? this.footerOpacity),
    );
  }
}

class HomeAppearanceRepository {
  const HomeAppearanceRepository._();

  static String get _userKey {
    final userId = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentUser?.id
        : null;
    return userId == null || userId.isEmpty ? 'local' : userId;
  }

  static String _key(String suffix) => 'sko_home_appearance_${_userKey}_$suffix';

  static Future<HomeAppearance> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultsMigrationKey = _key('defaults_20261003');
    if (!(prefs.getBool(defaultsMigrationKey) ?? false)) {
      await prefs.setDouble(_key('wallpaper_opacity'), 1.0);
      await prefs.setDouble(_key('button_opacity'), 0.8);
      await prefs.setDouble(_key('card_button_opacity'), 1.0);
      await prefs.setDouble(_key('card_opacity'), 0.8);
      await prefs.setDouble(_key('header_opacity'), 0.8);
      await prefs.setDouble(_key('footer_opacity'), 0.8);
      await prefs.setBool(defaultsMigrationKey, true);
    }
    return HomeAppearance(
      wallpaperPath: prefs.getString(_key('wallpaper_path')),
      wallpaperOpacity: _read(
        prefs,
        'wallpaper_opacity',
        fallback: 1,
      ),
      buttonOpacity: _read(prefs, 'button_opacity', fallback: 0.8),
      cardButtonOpacity: _read(
        prefs,
        'card_button_opacity',
        fallback: 1,
      ),
      cardOpacity: _read(prefs, 'card_opacity', fallback: 0.8),
      headerOpacity: _read(prefs, 'header_opacity', fallback: 0.8),
      footerOpacity: _read(prefs, 'footer_opacity', fallback: 0.8),
    );
  }

  static Future<void> save(HomeAppearance value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.wallpaperPath == null || value.wallpaperPath!.isEmpty) {
      await prefs.remove(_key('wallpaper_path'));
    } else {
      await prefs.setString(_key('wallpaper_path'), value.wallpaperPath!);
    }
    await prefs.setDouble(_key('wallpaper_opacity'), value.wallpaperOpacity);
    await prefs.setDouble(_key('button_opacity'), value.buttonOpacity);
    await prefs.setDouble(
      _key('card_button_opacity'),
      value.cardButtonOpacity,
    );
    await prefs.setDouble(_key('card_opacity'), value.cardOpacity);
    await prefs.setDouble(_key('header_opacity'), value.headerOpacity);
    await prefs.setDouble(_key('footer_opacity'), value.footerOpacity);
  }

  static double _read(
    SharedPreferences prefs,
    String key, {
    double fallback = 0.6,
  }) {
    return HomeAppearance.normalize(
      prefs.getDouble(_key(key)) ?? fallback,
    );
  }

  static Future<String?> storeWallpaper(XFile image) async {
    final dir = await getApplicationSupportDirectory();
    final wallpaperDir = Directory('${dir.path}/sko_wallpapers');
    if (!await wallpaperDir.exists()) await wallpaperDir.create(recursive: true);
    final extension = image.name.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
    final target = File('${wallpaperDir.path}/$_userKey$extension');
    await File(image.path).copy(target.path);
    return target.path;
  }
}

class HomeAppearanceSettingsPage extends StatefulWidget {
  const HomeAppearanceSettingsPage({super.key, required this.initial});
  final HomeAppearance initial;

  @override
  State<HomeAppearanceSettingsPage> createState() => _HomeAppearanceSettingsPageState();
}

class _HomeAppearanceSettingsPageState extends State<HomeAppearanceSettingsPage> {
  final _picker = ImagePicker();
  late HomeAppearance _value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  Future<void> _pickWallpaper() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 72,
      maxWidth: 1200,
    );
    if (image == null) return;
    final path = await HomeAppearanceRepository.storeWallpaper(image);
    if (!mounted || path == null) return;
    setState(() => _value = _value.copyWith(wallpaperPath: path));
  }

  Future<void> _persistCurrent() async {
    await HomeAppearanceRepository.save(_value);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await HomeAppearanceRepository.save(_value);
      if (!mounted) return;
      Navigator.of(context).pop(_value);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ホーム外観設定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Text('この設定はこのユーザーだけに保存され、他ユーザーへ影響しません。'),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.wallpaper_outlined),
              title: const Text('壁紙'),
              subtitle: Text(_value.wallpaperPath == null ? '未設定' : '設定済み'),
              trailing: Wrap(children: [
                IconButton(
                  tooltip: '壁紙を選ぶ',
                  onPressed: _pickWallpaper,
                  icon: const Icon(Icons.photo_library_outlined),
                ),
                if (_value.wallpaperPath != null)
                  IconButton(
                    tooltip: '壁紙を外す',
                    onPressed: () => setState(() => _value = _value.copyWith(clearWallpaper: true)),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ]),
            ),
          ),
          _slider('壁紙の透明度', _value.wallpaperOpacity, (v) => _value = _value.copyWith(wallpaperOpacity: v)),
          _slider(
            '機能ボタンの透明度',
            _value.buttonOpacity,
            (v) => _value = _value.copyWith(buttonOpacity: v),
          ),
          _slider(
            'カード上ボタンの透明度',
            _value.cardButtonOpacity,
            (v) => _value = _value.copyWith(cardButtonOpacity: v),
          ),
          _slider(
            'カードの透明度',
            _value.cardOpacity,
            (v) => _value = _value.copyWith(cardOpacity: v),
          ),
          _headerOpacityPreview(),
          _slider(
            'ヘッダーの透明度',
            _value.headerOpacity,
            (v) => _value = _value.copyWith(headerOpacity: v),
          ),
          _slider('フッターの透明度', _value.footerOpacity, (v) => _value = _value.copyWith(footerOpacity: v)),
          const SizedBox(height: 8),
          const Text('透明度は1〜100%です。変更値はその場で保存されます。0%にはできません。'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中…' : '確定して保存'),
          ),
        ],
      ),
    );
  }

  Widget _headerOpacityPreview() {
    final opacity = _value.headerOpacity;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ヘッダー透明度プレビュー',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Container(
              height: 54,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFBBD7F5),
                    Color(0xFFE4EEF8),
                    Color(0xFFBBD7F5),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: opacity),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  Center(
                    child: Text(
                      'ヘッダー ${(opacity * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> update) {
    final percent = (value * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))),
              Text('$percent%'),
            ]),
            Slider(
              value: value,
              min: 0.01,
              max: 1,
              divisions: 99,
              label: '$percent%',
              onChanged: (next) {
                setState(() => update(next));
                _persistCurrent();
              },
            ),
          ],
        ),
      ),
    );
  }
}