import '../../international/core/language_pack.dart';
import '../../international/language_controller.dart';

/// Labels for personal chat appearance; saved settings stay language independent.
class ChatAppearanceStrings {
  ChatAppearanceStrings._();

  static const _english = LanguagePack(
    languageCode: 'en',
    fallbackLanguageCode: 'ja',
    strings: {
      'チャット背景・透明度': 'Chat appearance',
      'このチャットだけの個人設定です。他のユーザーには反映されません。':
          'Personal settings for this chat only. Other users are not affected.',
      '壁紙なし': 'No wallpaper',
      '壁紙を読み込めません': 'Could not load wallpaper',
      '壁紙を選ぶ': 'Choose wallpaper',
      '壁紙を解除': 'Remove wallpaper',
      '壁紙の透明度': 'Wallpaper opacity',
      'ヘッダー・タブの透明度': 'Header and tab opacity',
      'フッターの透明度': 'Footer opacity',
      'メッセージ背景の透明度': 'Message background opacity',
      'このチャットに保存': 'Save for this chat',
    },
  );

  static String tr(String source) =>
      SkoLanguageController.isEnglish ? _english.translate(source) : source;
}
