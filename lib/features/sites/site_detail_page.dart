import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'site_cloud_repository.dart';
import 'site_page.dart';

class SiteDetailPage extends StatefulWidget {
  const SiteDetailPage({
    super.key,
    required this.site,
    required this.canManage,
    this.onComplete,
  });

  final SiteRecord site;
  final bool canManage;
  final Future<void> Function()? onComplete;

  @override
  State<SiteDetailPage> createState() => _SiteDetailPageState();
}

class _SiteDetailPageState extends State<SiteDetailPage> {
  final _repository = SiteCloudRepository.maybeCreate();
  final _picker = ImagePicker();
  List<SitePhotoRecord> _photos = const [];
  bool _loadingPhotos = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final repository = _repository;
    if (repository == null || widget.site.id.isEmpty) {
      setState(() => _loadingPhotos = false);
      return;
    }
    try {
      final photos = await repository.loadPhotos(widget.site.id);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loadingPhotos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPhotos = false);
    }
  }

  Future<void> _openMap(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;
    final uri = Uri.https('maps.apple.com', '/', {'q': value});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地図を開けませんでした')),
      );
    }
  }

  Future<void> _call(String phone) async {
    final value = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (value.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: value);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('電話を開始できませんでした')),
      );
    }
  }

  Future<void> _share() async {
    final repository = _repository;
    if (repository == null || widget.site.id.isEmpty) return;

    List<Map<String, dynamic>> targets;
    try {
      targets = await repository.loadSiteShareTargets();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('送信先会社を読み込めませんでした: $error')),
      );
      return;
    }
    if (!mounted) return;

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('接続済みの下請け会社・取引会社がありません')),
      );
      return;
    }

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('下請け会社・取引会社に共有'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('SKOアプリ内で接続済みの会社を選択してください。'),
                const SizedBox(height: 8),
                for (final target in targets)
                  CheckboxListTile(
                    value: selected.contains(
                      target['company_id']?.toString() ?? '',
                    ),
                    title: Text(
                      target['company_name']?.toString() ?? '会社',
                    ),
                    subtitle: Text(
                      target['relation_label']?.toString() ?? '',
                    ),
                    onChanged: (value) {
                      final id = target['company_id']?.toString() ?? '';
                      if (id.isEmpty) return;
                      setDialogState(() {
                        if (value == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text('選択した${selected.length}社へ送信'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selected.isEmpty) return;

    try {
      final count = await repository.sendSiteShare(
        siteId: widget.site.id,
        targetCompanyIds: selected,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count社へ現場データを送信しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('現場データを送信できませんでした: $error')),
      );
    }
  }

  Future<void> _requestComplete() async {
    final repository = _repository;
    if (repository == null || !widget.canManage) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('現場終了を申請しますか？'),
        content: const Text('現場は承認後に終了扱いになります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('承認申請を送る'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repository.submitInformationChange(
        siteId: widget.site.id,
        values: const {'status': 'completed'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現場終了の承認申請を送信しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('現場終了を申請できませんでした: $error')),
      );
    }
  }

  Future<void> _showCreator() async {
    final repository = _repository;
    final creatorName = widget.site.creatorName.trim();
    if (repository == null || creatorName.isEmpty) return;
    final worker = await repository.loadCreatorEmployee(creatorName);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('登録者の社員情報'),
        content: worker == null
            ? Text('登録者：$creatorName')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('氏名：${worker['name']?.toString() ?? creatorName}'),
                  if ((worker['role']?.toString().isNotEmpty ?? false))
                    Text('役割・職種：${worker['role']}'),
                  if ((worker['phone']?.toString().isNotEmpty ?? false))
                    Text('電話：${worker['phone']}'),
                  if ((worker['email']?.toString().isNotEmpty ?? false))
                    Text('メール：${worker['email']}'),
                ],
              ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => _SiteEditRequestPage(site: widget.site),
      ),
    );
    if (result == null || !mounted) return;
    final repository = _repository;
    if (repository == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('現場情報の変更を申請しますか？'),
        content: const Text('登録済みの現場情報は承認後に反映されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定して申請'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repository.submitInformationChange(
        siteId: widget.site.id,
        values: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('変更申請を送信しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('変更申請を送信できませんでした: $error')),
      );
    }
  }

  Future<void> _showPhotoPreview(
    SitePhotoRecord photo,
    int slot,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text('現場写真$slot'),
                actions: [
                  if (widget.canManage)
                    IconButton(
                      tooltip: '写真を変更',
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _pickPhoto(slot);
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  IconButton(
                    tooltip: '閉じる',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Image.network(
                    photo.signedUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickPhoto(int slot) async {
    final repository = _repository;
    if (repository == null) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('写真ライブラリから選択'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final image = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2200,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('現場写真$slotを登録しますか？'),
        content: const Text('既存現場の写真変更は承認後に反映されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定して送信'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final pending = await repository.uploadPhoto(
        siteId: widget.site.id,
        slot: slot,
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending ? '写真変更を承認待ちで送信しました' : '現場写真を登録しました',
          ),
        ),
      );
      await _loadPhotos();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真を送信できませんでした: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return Scaffold(
      appBar: AppBar(
        title: const Text('現場詳細'),
        actions: [
          IconButton(
            tooltip: '下請け会社・取引会社に共有',
            onPressed: _share,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (site.creatorName.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: const Text('登録者'),
              subtitle: Text(site.creatorName),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showCreator,
            ),
          Text(
            site.formalName.isNotEmpty ? site.formalName : site.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 12),
          _linkRow(
            icon: Icons.business_outlined,
            label: '取引先',
            value: site.customerName,
            onTap: site.customerName.isEmpty
                ? null
                : () => _openMap(site.customerName),
          ),
          _linkRow(
            icon: Icons.location_on_outlined,
            label: '現場住所',
            value: site.address,
            onTap:
                site.address.isEmpty ? null : () => _openMap(site.address),
          ),
          _linkRow(
            icon: Icons.train_outlined,
            label: '最寄駅',
            value: site.nearestStation,
            onTap: site.nearestStation.isEmpty
                ? null
                : () => _openMap(site.nearestStation),
          ),
          _linkRow(
            icon: Icons.badge_outlined,
            label: '現場責任者',
            value: site.representativeName.isNotEmpty
                ? site.representativeName
                : site.managerName,
          ),
          _linkRow(
            icon: Icons.phone_outlined,
            label: '電話番号',
            value: site.representativePhone,
            onTap: site.representativePhone.isEmpty
                ? null
                : () => _call(site.representativePhone),
          ),
          if (site.createdAt.isNotEmpty)
            Text('登録日: ${site.createdAt}'),
          if (site.updatedAt.isNotEmpty &&
              site.updatedAt != site.createdAt)
            Text('最終更新日: ${site.updatedAt}'),
          const SizedBox(height: 18),
          Text(
            '現場写真',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          if (_loadingPhotos)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              children: [
                for (var slot = 1; slot <= 3; slot++) ...[
                  Expanded(child: _photoCard(slot)),
                  if (slot < 3) const SizedBox(width: 8),
                ],
              ],
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('下請け会社・取引会社に共有'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('編集／登録'),
          ),
          if (widget.canManage &&
              widget.site.status != SiteStatus.completed) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _requestComplete,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('現場終了を承認申請'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photoCard(int slot) {
    SitePhotoRecord? photo;
    for (final item in _photos) {
      if (item.slot == slot) {
        photo = item;
        break;
      }
    }
    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        onTap: photo == null
            ? (widget.canManage ? () => _pickPhoto(slot) : null)
            : () => _showPhotoPreview(photo!, slot),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: photo == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_a_photo_outlined),
                    const SizedBox(height: 4),
                    Text('写真$slot'),
                  ],
                )
              : Image.network(
                  photo.signedUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
        ),
      ),
    );
  }

  Widget _linkRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      trailing: onTap == null ? null : const Icon(Icons.open_in_new),
      onTap: onTap,
    );
  }
}

class _SiteEditRequestPage extends StatefulWidget {
  const _SiteEditRequestPage({required this.site});
  final SiteRecord site;

  @override
  State<_SiteEditRequestPage> createState() => _SiteEditRequestPageState();
}

class _SiteEditRequestPageState extends State<_SiteEditRequestPage> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _station;
  late final TextEditingController _representative;
  late final TextEditingController _phone;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    _name = TextEditingController(
      text: site.formalName.isNotEmpty ? site.formalName : site.name,
    );
    _address = TextEditingController(text: site.address);
    _station = TextEditingController(text: site.nearestStation);
    _representative = TextEditingController(
      text: site.representativeName.isNotEmpty
          ? site.representativeName
          : site.managerName,
    );
    _phone = TextEditingController(text: site.representativePhone);
    _notes = TextEditingController(text: site.notes);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _address,
      _station,
      _representative,
      _phone,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('現場 編集／登録')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_name, '現場名'),
          _field(_address, '現場住所'),
          _field(_station, '最寄駅'),
          _field(_representative, '現場責任者名'),
          _field(_phone, '電話番号',
              keyboardType: TextInputType.phone),
          _field(_notes, '備考', maxLines: 3),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop({
              'name': _name.text.trim(),
              'formal_name': _name.text.trim(),
              'address': _address.text.trim(),
              'nearest_station': _station.text.trim(),
              'representative_name': _representative.text.trim(),
              'representative_phone': _phone.text.trim(),
              'notes': _notes.text.trim(),
            }),
            icon: const Icon(Icons.check),
            label: const Text('変更内容を確認'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
