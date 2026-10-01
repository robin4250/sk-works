import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'personal_appearance_preferences.dart';

class PersonalAppearanceSettingsPage extends StatefulWidget {
  const PersonalAppearanceSettingsPage({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  State<PersonalAppearanceSettingsPage> createState() =>
      _PersonalAppearanceSettingsPageState();
}

class _PersonalAppearanceSettingsPageState
    extends State<PersonalAppearanceSettingsPage> {
  final _picker = ImagePicker();
  PersonalAppearanceSettings _value = const PersonalAppearanceSettings();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await PersonalAppearancePreferences.load(widget.userId);
    if (!mounted) return;
    setState(() {
      _value = value;
      _loading = false;
    });
  }

  Future<void> _chooseWallpaper() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 68,
      maxWidth: 1280,
      maxHeight: 1600,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(() {
      _value = _value.copyWith(
        homeWallpaperBase64:
            PersonalAppearancePreferences.encodeWallpaper(bytes),
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await PersonalAppearancePreferences.save(widget.userId, _value);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _value.wallpaperBytes;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ホーム見た目設定',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  const Text(
                    '自分の端末・自分のアカウントだけに反映されます。',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: bytes == null
                          ? const Center(
                              child: Text('壁紙未設定'),
                            )
                          : Image.memory(bytes, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _chooseWallpaper,
                          icon: const Icon(Icons.wallpaper_outlined),
                          label: const Text('壁紙を選ぶ'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: bytes == null
                              ? null
                              : () => setState(
                                    () => _value =
                                        _value.copyWith(clearWallpaper: true),
                                  ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('壁紙を外す'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _opacitySlider(
                    '壁紙',
                    _value.wallpaperOpacity,
                    (value) => _value =
                        _value.copyWith(wallpaperOpacity: value),
                  ),
                  _opacitySlider(
                    'ボタン',
                    _value.buttonOpacity,
                    (value) =>
                        _value = _value.copyWith(buttonOpacity: value),
                  ),
                  _opacitySlider(
                    'カード',
                    _value.cardOpacity,
                    (value) => _value = _value.copyWith(cardOpacity: value),
                  ),
                  _opacitySlider(
                    'ヘッダー',
                    _value.headerOpacity,
                    (value) =>
                        _value = _value.copyWith(headerOpacity: value),
                  ),
                  _opacitySlider(
                    'フッター',
                    _value.footerOpacity,
                    (value) =>
                        _value = _value.copyWith(footerOpacity: value),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? '保存中…' : '確定して保存'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '透明度は1％〜100％です。0％にはできません。',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _opacitySlider(
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label + 'の透明度',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(value.toString() + '％'),
              ],
            ),
            Slider(
              value: value.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: value.toString() + '％',
              onChanged: (next) {
                setState(() => onChanged(next.round().clamp(1, 100)));
              },
            ),
          ],
        ),
      ),
    );
  }
}
