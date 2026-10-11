import '../../international/core/language_pack.dart';
import '../../international/language_controller.dart';

/// Localized labels for the friend list, picker and request dialogs.
/// Interpolated names, identifiers and server details are never translated.
class ChatFriendsStrings {
  ChatFriendsStrings._();

  static const _english = LanguagePack(
    languageCode: 'en',
    fallbackLanguageCode: 'ja',
    strings: {
      '友達機能を利用できません。': 'Friends are unavailable.',
      '友達一覧': 'Friends list',
      '友達を招待': 'Invite friends',
      '友達': 'Friends',
      '友達はまだいません': 'No friends yet',
      'SKOユーザー': 'SKO user',
      '自分のSKO ID': 'My SKO ID',
      'SKO ID検索': 'Search by SKO ID',
      '検索': 'Search',
      '申請': 'Request',
      '届いた申請': 'Incoming requests',
      '拒否': 'Decline',
      '承認': 'Accept',
      '申請中': 'Sent requests',
      '承認待ち': 'Awaiting approval',
      '友達から削除': 'Remove friend',
      '友達申請を送りますか？': 'Send a friend request?',
      '戻る': 'Back',
      '申請する': 'Send request',
      '友達申請を送信しました': 'Friend request sent',
      '友達申請を承認しますか？': 'Accept this friend request?',
      '友達申請を拒否しますか？': 'Decline this friend request?',
      '承認する': 'Accept',
      '拒否する': 'Decline',
      '友達から削除しますか？': 'Remove this friend?',
      '削除する': 'Remove',
      '該当するSKO IDが見つかりません': 'No matching SKO ID found',
      '{name} さんへ友達申請を送信します。': 'Send a friend request to {name}.',
      '検索できませんでした: {error}': 'Could not search: {error}',
      '友達申請を送信できませんでした: {error}': 'Could not send the friend request: {error}',
      '友達一覧を読み込めませんでした: {error}': 'Could not load friends: {error}',
      '友達申請を更新できませんでした: {error}':
          'Could not update the friend request: {error}',
      '友達から削除できませんでした: {error}': 'Could not remove the friend: {error}',
    },
  );
  static const _japanese = LanguagePack(
    languageCode: 'ja',
    fallbackLanguageCode: 'ja',
  );

  static LanguagePack get _pack =>
      SkoLanguageController.isEnglish ? _english : _japanese;

  static String tr(String source) => _pack.translate(source);
  static String format(String source, Map<String, Object?> values) =>
      _pack.format(source, values);
}
