import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../international/language_controller.dart';
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

  String _tr(String ja, String en) =>
      SkoLanguageController.isEnglish ? en : ja;

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
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': value,
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('地図を開けませんでした', 'Could not open the map'))),
      );
    }
  }

  Future<void> _call(String phone) async {
    final value = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (value.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: value);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('電話を開始できませんでした', 'Could not start the call'))),
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
        SnackBar(content: Text('${_tr('送信先会社を読み込めませんでした', 'Could not load recipient companies')}: $error')),
      );
      return;
    }
    if (!mounted) return;

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('接続済みの下請け会社・取引会社がありません', 'There are no connected subcontractor or business partner companies'))),
      );
      return;
    }

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_tr('下請け会社・取引会社に共有', 'Share with Subcontractors / Business Partners')),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(_tr('SKOアプリ内で接続済みの会社を選択してください。', 'Select connected companies in SKO.')),
                const SizedBox(height: 5),
                for (final target in targets)
                  CheckboxListTile(
                    value: selected.contains(
                      target['company_id']?.toString() ?? '',
                    ),
                    title: Text(
                      target['company_name']?.toString() ?? _tr('会社', 'Company'),
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
              child: Text(_tr('戻る', 'Back')),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(SkoLanguageController.isEnglish ? 'Send to ${selected.length} selected companies' : '選択した${selected.length}社へ送信'),
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
        SnackBar(content: Text(SkoLanguageController.isEnglish ? 'Site data sent to $count companies' : '$count社へ現場データを送信しました')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_tr('現場データを送信できませんでした', 'Could not send site data')}: $error')),
      );
    }
  }

  Future<void> _requestComplete() async {
    final repository = _repository;
    if (repository == null || !widget.canManage) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr('現場終了を申請しますか？', 'Request site completion?')),
        content: Text(_tr('現場は承認後に終了扱いになります。', 'The site will be marked complete after approval.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr('戻る', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_tr('承認申請を送る', 'Send Approval Request')),
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
        SnackBar(content: Text(_tr('現場終了の承認申請を送信しました', 'Site completion approval request sent'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_tr('現場終了を申請できませんでした', 'Could not request site completion')}: $error')),
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
        title: Text(_tr('登録者の社員情報', 'Registrant Employee Information')),
        content: worker == null
            ? Text(SkoLanguageController.isEnglish ? 'Registrant: $creatorName' : '登録者：$creatorName')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(SkoLanguageController.isEnglish ? 'Name: ${worker['name']?.toString() ?? creatorName}' : '氏名：${worker['name']?.toString() ?? creatorName}'),
                  if ((worker['role']?.toString().isNotEmpty ?? false))
                    Text(SkoLanguageController.isEnglish ? 'Role / Job: ${worker['role']}' : '役割・職種：${worker['role']}'),
                  if ((worker['phone']?.toString().isNotEmpty ?? false))
                    Text(SkoLanguageController.isEnglish ? 'Phone: ${worker['phone']}' : '電話：${worker['phone']}'),
                  if ((worker['email']?.toString().isNotEmpty ?? false))
                    Text(SkoLanguageController.isEnglish ? 'Email: ${worker['email']}' : 'メール：${worker['email']}'),
                ],
              ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_tr('閉じる', 'Close')),
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
        title: Text(_tr('現場情報の変更を申請しますか？', 'Request changes to site information?')),
        content: Text(_tr('登録済みの現場情報は承認後に反映されます。', 'Changes to registered site information are applied after approval.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('戻る', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('確定して申請', 'Confirm and Submit')),
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
        SnackBar(content: Text(_tr('変更申請を送信しました', 'Change request sent'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_tr('変更申請を送信できませんでした', 'Could not send change request')}: $error')),
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
                title: Text(SkoLanguageController.isEnglish ? 'Site Photo $slot' : '現場写真$slot'),
                actions: [
                  if (widget.canManage)
                    IconButton(
                      tooltip: _tr('写真を変更', 'Change Photo'),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _pickPhoto(slot);
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  IconButton(
                    tooltip: _tr('閉じる', 'Close'),
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
              title: Text(_tr('カメラで撮影', 'Take Photo with Camera')),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(_tr('写真ライブラリから選択', 'Choose from Photo Library')),
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
        title: Text(SkoLanguageController.isEnglish ? 'Register site photo $slot?' : '現場写真$slotを登録しますか？'),
        content: Text(_tr('既存現場の写真変更は承認後に反映されます。', 'Photo changes for an existing site are applied after approval.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_tr('戻る', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_tr('確定して送信', 'Confirm and Send')),
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
            pending ? _tr('写真変更を承認待ちで送信しました', 'Photo change sent for approval') : _tr('現場写真を登録しました', 'Site photo registered'),
          ),
        ),
      );
      await _loadPhotos();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_tr('写真を送信できませんでした', 'Could not send photo')}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('現場詳細', 'Site Details')),
        actions: [
          IconButton(
            tooltip: _tr('下請け会社・取引会社に共有', 'Share with Subcontractors / Business Partners'),
            onPressed: _share,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
        children: [
          if (site.creatorName.isNotEmpty)
            InkWell(
              onTap: _showCreator,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 17),
                    const SizedBox(width: 6),
                    Text(
                      _tr('登録者 ', 'Registrant '),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    Expanded(
                      child: Text(
                        site.creatorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 17),
                  ],
                ),
              ),
            ),
          Text(
            site.formalName.isNotEmpty ? site.formalName : site.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  height: 1.1,
                ),
          ),
          const SizedBox(height: 4),
          _linkRow(
            icon: Icons.apartment_outlined,
            label: _tr('現場名', 'Site Name'),
            value: site.name,
          ),
          _linkRow(
            icon: Icons.business_outlined,
            label: _tr('取引先', 'Business Partner'),
            value: site.customerName,
            onTap: site.customerName.isEmpty
                ? null
                : () => _openMap(site.customerName),
          ),
          _linkRow(
            icon: Icons.info_outline,
            label: _tr('状態', 'Status'),
            value: site.status.label,
          ),
          _linkRow(
            icon: Icons.text_fields_outlined,
            label: _tr('現場正式名称', 'Formal Site Name'),
            value: site.formalName,
          ),
          _linkRow(
            icon: Icons.person_pin_outlined,
            label: _tr('担当者', 'Person in Charge'),
            value: site.managerName,
          ),
          _linkRow(
            icon: Icons.badge_outlined,
            label: _tr('現場責任者', 'Site Manager'),
            value: site.representativeName,
          ),
          _linkRow(
            icon: Icons.phone_outlined,
            label: _tr('責任者電話番号', 'Manager Phone'),
            value: site.representativePhone,
            onTap: site.representativePhone.isEmpty
                ? null
                : () => _call(site.representativePhone),
          ),
          _linkRow(
            icon: Icons.location_on_outlined,
            label: _tr('現場住所', 'Site Address'),
            value: site.address,
            onTap:
                site.address.isEmpty ? null : () => _openMap(site.address),
          ),
          _linkRow(
            icon: Icons.train_outlined,
            label: _tr('最寄りの駅', 'Nearest Station'),
            value: site.nearestStation,
            onTap: site.nearestStation.isEmpty
                ? null
                : () => _openMap(site.nearestStation),
          ),
          _linkRow(
            icon: Icons.event_available_outlined,
            label: _tr('開始日', 'Start Date'),
            value: site.startDate,
          ),
          _linkRow(
            icon: Icons.event_busy_outlined,
            label: _tr('終了日', 'End Date'),
            value: site.endDate,
          ),
          _linkRow(
            icon: Icons.notes_outlined,
            label: _tr('備考', 'Notes'),
            value: site.notes,
          ),
          if (site.createdAt.isNotEmpty ||
              (site.updatedAt.isNotEmpty && site.updatedAt != site.createdAt))
            Text(
              [
                if (site.createdAt.isNotEmpty) (SkoLanguageController.isEnglish ? 'Registered: ${site.createdAt}' : '登録日: ${site.createdAt}'),
                if (site.updatedAt.isNotEmpty && site.updatedAt != site.createdAt)
                  (SkoLanguageController.isEnglish ? 'Last updated: ${site.updatedAt}' : '最終更新日: ${site.updatedAt}'),
              ].join('　'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          const SizedBox(height: 10),
          Text(
            _tr('現場写真', 'Site Photos'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 5),
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
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: FilledButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.ios_share_outlined),
            label: Text(_tr('下請け会社・取引会社に共有', 'Share with Subcontractors / Business Partners')),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(_tr('編集／登録', 'Edit / Register')),
            ),
          ),
          if (widget.canManage &&
              widget.site.status != SiteStatus.completed) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
              onPressed: _requestComplete,
              icon: const Icon(Icons.archive_outlined),
              label: Text(_tr('現場終了を承認申請', 'Request Site Completion')),
              ),
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
      aspectRatio: 1.55,
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
                    Text(SkoLanguageController.isEnglish ? 'Photo $slot' : '写真$slot'),
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
    final displayValue = value.trim().isEmpty
        ? _tr('未登録', 'Not registered')
        : value;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 24,
      leading: Icon(icon, size: 18),
      title: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        displayValue,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
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
  final _repository = SiteCloudRepository.maybeCreate();

  String _tr(String ja, String en) =>
      SkoLanguageController.isEnglish ? en : ja;

  late final TextEditingController _name;
  late final TextEditingController _formalName;
  late final TextEditingController _representative;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _station;
  late final TextEditingController _startDate;
  late final TextEditingController _endDate;
  late final TextEditingController _notes;

  List<SiteTradeCompanyOption> _tradeCompanies = const [];
  List<SiteManagerOption> _managers = const [];
  String? _customerId;
  String? _managerWorkerId;
  late SiteStatus _status;
  bool _loadingOptions = true;
  String? _optionError;

  @override
  void initState() {
    super.initState();
    final site = widget.site;
    _name = TextEditingController(text: site.name);
    _formalName = TextEditingController(text: site.formalName);
    _representative = TextEditingController(text: site.representativeName);
    _phone = TextEditingController(text: site.representativePhone);
    _address = TextEditingController(text: site.address);
    _station = TextEditingController(text: site.nearestStation);
    _startDate = TextEditingController(text: site.startDate);
    _endDate = TextEditingController(text: site.endDate);
    _notes = TextEditingController(text: site.notes);
    _customerId = site.customerId.isEmpty ? null : site.customerId;
    _managerWorkerId =
        site.managerWorkerId.isEmpty ? null : site.managerWorkerId;
    _status = site.status;
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final repository = _repository;
    if (repository == null) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionError = _tr(
          '取引会社・担当者を読み込めませんでした',
          'Could not load business partners or managers',
        );
      });
      return;
    }
    try {
      final tradeCompanies = await repository.loadCustomerTradeCompanies();
      final managers = await repository.loadSiteManagers();

      final customerItems = <SiteTradeCompanyOption>[...tradeCompanies];
      if (_customerId != null &&
          !customerItems.any((item) => item.customerId == _customerId) &&
          widget.site.customerName.isNotEmpty) {
        customerItems.insert(
          0,
          SiteTradeCompanyOption(
            tradeCompanyId: '',
            customerId: _customerId!,
            name: widget.site.customerName,
          ),
        );
      }

      final managerItems = <SiteManagerOption>[...managers];
      if (_managerWorkerId != null &&
          !managerItems.any((item) => item.workerId == _managerWorkerId) &&
          widget.site.managerName.isNotEmpty) {
        managerItems.insert(
          0,
          SiteManagerOption(
            workerId: _managerWorkerId!,
            name: widget.site.managerName,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _tradeCompanies = customerItems;
        _managers = managerItems;
        _loadingOptions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _optionError = error.toString();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _formalName,
      _representative,
      _phone,
      _address,
      _station,
      _startDate,
      _endDate,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _dbStatus(SiteStatus value) =>
      value == SiteStatus.preparing ? 'preparation' : value.name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tr('現場 編集／登録', 'Edit / Register Site'))),
      body: _loadingOptions
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_optionError != null) ...[
                  Text(
                    _optionError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                _field(_name, _tr('現場名', 'Site Name')),
                DropdownButtonFormField<String>(
                  value: _customerId,
                  decoration: InputDecoration(
                    labelText: _tr('取引先', 'Business Partner'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final item in _tradeCompanies)
                      DropdownMenuItem(
                        value: item.customerId,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _customerId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<SiteStatus>(
                  value: _status,
                  decoration: InputDecoration(
                    labelText: _tr('状態', 'Status'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in SiteStatus.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? _status),
                ),
                const SizedBox(height: 12),
                _field(_formalName, _tr('現場正式名称', 'Formal Site Name')),
                DropdownButtonFormField<String?>(
                  value: _managerWorkerId,
                  decoration: InputDecoration(
                    labelText: _tr('担当者', 'Person in Charge'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(_tr('未設定', 'Not set')),
                    ),
                    for (final item in _managers)
                      DropdownMenuItem<String?>(
                        value: item.workerId,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _managerWorkerId = value),
                ),
                const SizedBox(height: 12),
                _field(
                  _representative,
                  _tr('現場責任者', 'Site Manager'),
                ),
                _field(
                  _phone,
                  _tr('責任者電話番号', 'Manager Phone'),
                  keyboardType: TextInputType.phone,
                ),
                _field(_address, _tr('現場住所', 'Site Address')),
                _field(_station, _tr('最寄りの駅', 'Nearest Station')),
                _field(_startDate, _tr('開始日', 'Start Date')),
                _field(_endDate, _tr('終了日', 'End Date')),
                _field(_notes, _tr('備考', 'Notes'), maxLines: 3),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check),
                  label: Text(_tr('変更内容を確認', 'Review Changes')),
                ),
              ],
            ),
    );
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('現場名を入力してください', 'Enter a site name'))),
      );
      return;
    }
    if (_customerId == null || _customerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              '登録済みの取引会社から取引先を選択してください',
              'Select a registered business partner',
            ),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop({
      'name': _name.text.trim(),
      'customer_id': _customerId!,
      'status': _dbStatus(_status),
      'formal_name': _formalName.text.trim(),
      'manager_worker_id': _managerWorkerId ?? '',
      'representative_name': _representative.text.trim(),
      'representative_phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'nearest_station': _station.text.trim(),
      'starts_at': _startDate.text.trim(),
      'ends_at': _endDate.text.trim(),
      'notes': _notes.text.trim(),
    });
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
