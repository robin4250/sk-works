import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notifications/notification_bell.dart';
import 'site_cloud_repository.dart';
import 'site_page.dart';

class SiteCloudDetailPage extends StatefulWidget {
  const SiteCloudDetailPage({
    super.key,
    required this.site,
    required this.canManage,
  });

  final SiteRecord site;
  final bool canManage;

  @override
  State<SiteCloudDetailPage> createState() => _SiteCloudDetailPageState();
}

class _SiteCloudDetailPageState extends State<SiteCloudDetailPage> {
  final _repository = SiteCloudRepository.maybeCreate();
  final _picker = ImagePicker();
  List<SitePhotoRecord> _photos = const [];
  bool _loadingPhotos = true;
  bool _busy = false;

  SiteRecord get site => widget.site;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final repository = _repository;
    if (repository == null || site.id.isEmpty) {
      if (mounted) setState(() => _loadingPhotos = false);
      return;
    }
    try {
      final photos = await repository.loadPhotos(site.id);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loadingPhotos = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPhotos = false);
    }
  }

  Future<void> _openMap(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;
    final uri = Uri.https('maps.apple.com', '/', {'q': value});
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地図を開けませんでした')),
      );
    }
  }

  Future<void> _callPhone() async {
    final phone = site.representativePhone.trim();
    if (phone.isEmpty) return;
    final opened = await launchUrl(
      Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('電話アプリを開けませんでした')),
      );
    }
  }

  Future<void> _shareWithCustomer() async {
    final lines = <String>[
      site.formalName.isNotEmpty ? site.formalName : site.name,
      if (site.address.isNotEmpty) '現場住所：' + site.address,
      if (site.nearestStation.isNotEmpty) '最寄駅：' + site.nearestStation,
      if (site.representativeName.isNotEmpty)
        '現場責任者：' + site.representativeName,
      if (site.representativePhone.isNotEmpty)
        '電話：' + site.representativePhone,
    ];
    await SharePlus.instance.share(
      ShareParams(
        text: lines.join('\n'),
        subject: site.name + ' 現場情報',
      ),
    );
  }

  Future<void> _showCreator() async {
    final repository = _repository;
    if (repository == null || site.creatorName.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final worker = await repository.loadCreatorEmployee(site.creatorName);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('登録者の社員情報'),
          content: worker == null
              ? Text('登録者：' + site.creatorName)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('氏名：' + (worker['name']?.toString() ?? site.creatorName)),
                    if ((worker['kana']?.toString().isNotEmpty ?? false))
                      Text('フリガナ：' + worker['kana'].toString()),
                    if ((worker['role']?.toString().isNotEmpty ?? false))
                      Text('役割・職種：' + worker['role'].toString()),
                    if ((worker['phone']?.toString().isNotEmpty ?? false))
                      Text('電話：' + worker['phone'].toString()),
                    if ((worker['email']?.toString().isNotEmpty ?? false))
                      Text('メール：' + worker['email'].toString()),
                    if (worker['experience_years'] != null)
                      Text('経験年数：' + worker['experience_years'].toString() + '年'),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final values = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => SiteInformationEditPage(site: site),
      ),
    );
    final repository = _repository;
    if (values == null || repository == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('現場情報の変更申請'),
        content: const Text(
          '登録済み内容の変更は承認後に反映されます。変更内容を申請しますか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('確定して申請'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await repository.submitInformationChange(
        siteId: site.id,
        values: values,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('現場情報の変更を申請しました。承認後に反映されます'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('変更申請できませんでした: ' + error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto(int slot) async {
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
              title: const Text('写真から選ぶ'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
    );
    if (image == null) return;
    final repository = _repository;
    if (repository == null) return;

    setState(() => _busy = true);
    try {
      final pending = await repository.uploadPhoto(
        siteId: site.id,
        slot: slot,
        bytes: await image.readAsBytes(),
      );
      if (!mounted) return;
      await _loadPhotos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending
                ? '写真' + slot.toString() + 'を変更申請しました。承認後に反映されます'
                : '写真' + slot.toString() + 'を登録しました',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写真を登録できませんでした: ' + error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SitePhotoRecord? _photoFor(int slot) {
    for (final photo in _photos) {
      if (photo.slot == slot) return photo;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final updatedDiffers =
        site.updatedAt.isNotEmpty && site.updatedAt != site.createdAt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('現場詳細', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: const [SkoNotificationBell()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (site.creatorName.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: const Text('登録者'),
                  subtitle: Text(site.creatorName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _showCreator,
                ),
              ),
            Text(
              site.formalName.isNotEmpty ? site.formalName : site.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            if (site.formalName.isNotEmpty && site.formalName != site.name)
              Text(site.name),
            const SizedBox(height: 10),
            _LinkRow(
              icon: Icons.business_outlined,
              label: '取引先',
              value: site.customerName,
              onTap: site.customerName.isEmpty
                  ? null
                  : () => _openMap(site.customerName),
            ),
            _LinkRow(
              icon: Icons.location_on_outlined,
              label: '現場住所',
              value: site.address,
              onTap: site.address.isEmpty ? null : () => _openMap(site.address),
            ),
            _LinkRow(
              icon: Icons.train_outlined,
              label: '最寄駅',
              value: site.nearestStation,
              onTap: site.nearestStation.isEmpty
                  ? null
                  : () => _openMap(site.nearestStation),
            ),
            _LinkRow(
              icon: Icons.engineering_outlined,
              label: '現場責任者',
              value: site.representativeName.isNotEmpty
                  ? site.representativeName
                  : site.managerName,
            ),
            _LinkRow(
              icon: Icons.phone_outlined,
              label: '電話番号',
              value: site.representativePhone,
              onTap: site.representativePhone.isEmpty ? null : _callPhone,
            ),
            if (site.createdAt.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('登録日'),
                subtitle: Text(site.createdAt),
              ),
            if (updatedDiffers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.update_outlined),
                title: const Text('最終更新日'),
                subtitle: Text(site.updatedAt),
              ),
            const SizedBox(height: 12),
            Text(
              '現場写真',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                    if (slot > 1) const SizedBox(width: 8),
                    Expanded(
                      child: _PhotoSlot(
                        slot: slot,
                        photo: _photoFor(slot),
                        enabled: widget.canManage && !_busy,
                        onTap: () => _pickPhoto(slot),
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _shareWithCustomer,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('取引先に共有'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('編集／登録'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.slot,
    required this.photo,
    required this.enabled,
    required this.onTap,
  });

  final int slot;
  final SitePhotoRecord? photo;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: photo == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_a_photo_outlined),
                    const SizedBox(height: 6),
                    Text('写真' + slot.toString()),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(photo!.signedUrl, fit: BoxFit.cover),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        color: Colors.black54,
                        child: Text(
                          '写真' + slot.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      trailing: onTap == null
          ? null
          : const Icon(Icons.open_in_new_outlined, size: 18),
      onTap: onTap,
    );
  }
}

class SiteInformationEditPage extends StatefulWidget {
  const SiteInformationEditPage({super.key, required this.site});

  final SiteRecord site;

  @override
  State<SiteInformationEditPage> createState() =>
      _SiteInformationEditPageState();
}

class _SiteInformationEditPageState extends State<SiteInformationEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _formalName;
  late final TextEditingController _address;
  late final TextEditingController _station;
  late final TextEditingController _representativeName;
  late final TextEditingController _representativePhone;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.site.name);
    _formalName = TextEditingController(text: widget.site.formalName);
    _address = TextEditingController(text: widget.site.address);
    _station = TextEditingController(text: widget.site.nearestStation);
    _representativeName =
        TextEditingController(text: widget.site.representativeName);
    _representativePhone =
        TextEditingController(text: widget.site.representativePhone);
    _notes = TextEditingController(text: widget.site.notes);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _formalName,
      _address,
      _station,
      _representativeName,
      _representativePhone,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('現場情報 編集／登録')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_name, '現場名'),
            _field(_formalName, '現場正式名称'),
            _field(_address, '現場住所'),
            _field(_station, '最寄駅'),
            _field(_representativeName, '現場責任者名'),
            _field(
              _representativePhone,
              '電話番号',
              keyboardType: TextInputType.phone,
            ),
            _field(_notes, '備考', maxLines: 3),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Text('変更内容を確認'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
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

  void _submit() {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現場名を入力してください')),
      );
      return;
    }
    Navigator.pop(
      context,
      <String, String>{
        'name': _name.text.trim(),
        'formal_name': _formalName.text.trim(),
        'address': _address.text.trim(),
        'nearest_station': _station.text.trim(),
        'representative_name': _representativeName.text.trim(),
        'representative_phone': _representativePhone.text.trim(),
        'notes': _notes.text.trim(),
      },
    );
  }
}
