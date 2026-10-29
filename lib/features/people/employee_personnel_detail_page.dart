import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'employee_personnel_edit_page.dart';
import 'employee_bank_account_section.dart';
import 'employee_portrait_registration_page.dart';
import '../auth/secondary_protected_page.dart';
import 'employee_retirement_page.dart';
import 'employee_personnel_print_page.dart';
import 'people_page.dart';
import 'people_cloud_repository.dart';
import 'personnel_bundle_send_page.dart';
import 'phone_display.dart';

class EmployeePersonnelDetailPage extends StatelessWidget {
  const EmployeePersonnelDetailPage({
    super.key,
    required this.record,
    required this.allEmployees,
    required this.companyName,
    this.canManage = true,
    required this.canViewFamily,
    this.portraitLoader,
    this.portraitRegistrationBuilder,
    this.privacySession,
    bool privacyResolved=false,
  }) : _privacyResolved=privacyResolved;

  final PersonRecord record;
  final List<PersonRecord> allEmployees;
  final String companyName;
  final bool canManage;
  final bool canViewFamily;
  final Future<String?> Function()? portraitLoader;
  @visibleForTesting
  final Widget Function(PersonnelPrivacySession, String, String)? portraitRegistrationBuilder;
  final PersonnelPrivacySession? privacySession;
  final bool _privacyResolved;

  Future<bool?> _chooseScope(BuildContext context, String action) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: const Text('社員一覧'),
              subtitle: Text('社員一覧を$action'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('個別'),
              subtitle: Text('${record.name}さんだけを$action'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final all = await _chooseScope(context, '送信');
    if (all == null || !context.mounted) return;
    final session=privacySession;
    final displayCompany=companyName;
    final targets = session==null ? (all ? allEmployees : [record])
      : (all ? allEmployees : [record]).map((row)=>PersonRecord(id:row.id,kind:row.kind,name:'')).toList(growable:false);
    final workerIds=targets.map((row)=>row.id).toSet();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeePersonnelPrintPage(
          companyName: displayCompany,
          privacySession: session,
          records: targets,
          action: EmployeePersonnelPreviewAction.send,
          onConfirmSend: (previewContext) async {
            await Navigator.of(previewContext).push<bool>(
              MaterialPageRoute(
                builder: (_) => PersonnelBundleSendPage(
                  workerIds: workerIds,
                  privacySession: session,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _print(BuildContext context) async {
    final all = await _chooseScope(context, '印刷');
    if (all == null || !context.mounted) return;
    final session=privacySession;
    final displayCompany=companyName;
    final targets = session==null ? (all ? allEmployees : [record])
      : (all ? allEmployees : [record]).map((row)=>PersonRecord(id:row.id,kind:row.kind,name:'')).toList(growable:false);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeePersonnelPrintPage(
          companyName: displayCompany,
          privacySession: session,
          records: targets,
        ),
      ),
    );
  }

  void _edit(BuildContext context) {
    final session=privacySession;
    if(session==null){Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>EmployeePersonnelEditPage(record:record)));return;}
    final id=record.id;
    Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>PersonnelPrivacyView(session:session,builder:(context,rows){
      final current=rows.where((row)=>row['id']?.toString()==id).toList(growable:false);
      if(session.snapshot?.canManage!=true||current.length!=1||current.single['personnelBasicOnly']==true)return const Center(child:Text('編集権限を確認できません。'));
      return EmployeePersonnelEditPage(record:PersonRecord.fromJson(current.single),privacySession:session);
    })));
  }

  Future<void> _retire(BuildContext context) async {
    final session = privacySession;
    if (session == null || !canManage || !record.active) return;
    try {
      await session.read(workerIds: {record.id});
      session.verify(session.epoch);
      if (session.snapshot?.canManage != true || !context.mounted) return;
      final retired = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PersonnelPrivacyView(session: session, builder: (context, rows) {
          final current = rows.where((row) => row['id'] == record.id).toList();
          if (session.snapshot?.canManage != true || current.length != 1 ||
              current.single['active'] != true) {
            return const Center(child: Text('対象または管理権限を確認できません。'));
          }
          return SecondaryProtectedPage(title: '退職手続き',
            child: EmployeeRetirementPage(companyId: session.company,
              workerId: record.id, workerName: record.name, privacySession: session));
        }),
      ));
      await session.refresh();
      if (retired == true && context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('対象と管理権限を再確認してください。')));
      }
    }
  }

  Future<void> _callPhone(BuildContext context, String phone) async {
    final session=privacySession;
    if(session!=null){try{await session.read(workerIds:{record.id});session.verify(session.epoch);}catch(_){return;}}
    if(!context.mounted)return;
    final domestic = domesticPhoneDisplay(phone);
    final dial = domestic.replaceAll(RegExp(r'[^0-9+]'), '');
    if (dial.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: dial);
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('電話を開始できませんでした')));
    }
  }

  Future<void> _openGoogleMap(BuildContext context, String address) async {
    final query = address.trim();
    if (query.isEmpty) return;
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Googleマップを開けませんでした')));
    }
  }

  Widget _actionCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          value.trim().isEmpty ? '未登録' : value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: onTap == null ? null : Theme.of(context).colorScheme.primary,
            decoration: onTap == null ? null : TextDecoration.underline,
          ),
        ),
        trailing: onTap == null ? null : const Icon(Icons.open_in_new),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session=privacySession;
    if(session!=null&&!_privacyResolved) {
      return PersonnelPrivacyView(session:session,builder:(context,raw){
        final current=raw.where((row)=>row['id']?.toString()==record.id).toList(growable:false);
        if(current.length!=1)return const Center(child:Text('対象の社員情報を表示できません。'));
        return EmployeePersonnelDetailPage(record:PersonRecord.fromJson(current.single),
          allEmployees:raw.map(PersonRecord.fromJson).toList(growable:false),
          companyName:companyName,canManage:session.snapshot!.canManage&&current.single['personnelBasicOnly']!=true,canViewFamily:current.single['personnelBasicOnly']!=true,
          portraitLoader:portraitLoader,portraitRegistrationBuilder:portraitRegistrationBuilder,privacySession:session,privacyResolved:true);
      });
    }
    final rows = <(String, String)>[
      ('社員番号', record.employeeNumber),
      ('名前', record.name),
      ('区分', record.kind.label),
      ('血液型', record.bloodType),
      ('所属', record.department),
      ('職種', record.role),
      ('生年月日', record.birthDate.replaceAll('-', '/')),
      ('入社日', record.hireDate.replaceAll('-', '/')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '社員情報',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (canManage && record.active && privacySession != null)
              OutlinedButton.icon(onPressed: () => _retire(context),
                icon: const Icon(Icons.person_remove_outlined), label: const Text('退職手続き')),
            if (!record.active) const Text('退職者'),
            if (canManage && privacySession != null)
              _EmployeePortraitEntry(
                key: ValueKey('employee-portrait-entry:${privacySession!.company}:${record.id}'),
                session: privacySession!, workerId: record.id, loader: portraitLoader,
                registrationBuilder: () => portraitRegistrationBuilder?.call(privacySession!, record.id, companyName)
                  ?? EmployeePortraitRegistrationPage(privacySession: privacySession!,
                    workerId: record.id, companyName: companyName))
            else
              _PersonnelPortrait(key: ValueKey(record.id), loader: portraitLoader),
            if (privacySession != null)
              EmployeeBankAccountSection(
                key: ValueKey('employee-bank:${privacySession!.company}:${record.id}'),
                companyId: privacySession!.company, workerId: record.id, employeeName: record.name),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(2),
                },
                border: TableBorder.all(color: Theme.of(context).dividerColor),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (final row in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(row.$1),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            row.$2.trim().isEmpty ? '未登録' : row.$2,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            _actionCard(
              context,
              label: '電話番号',
              value: domesticPhoneDisplay(record.phone),
              icon: Icons.phone_outlined,
              onTap: record.phone.trim().isEmpty
                  ? null
                  : () => _callPhone(context, record.phone),
            ),
            _actionCard(
              context,
              label: '住所',
              value: record.address,
              icon: Icons.map_outlined,
              onTap: record.address.trim().isEmpty
                  ? null
                  : () => _openGoogleMap(context, record.address),
            ),
            Card(
              child: ListTile(
                title: const Text('緊急連絡先氏名'),
                subtitle: Text(
                  record.emergencyName.trim().isEmpty
                      ? '未登録'
                      : record.emergencyName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('続柄'),
                subtitle: Text(
                  record.emergencyRelation.trim().isEmpty
                      ? '未登録'
                      : record.emergencyRelation,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            _actionCard(
              context,
              label: '緊急連絡先電話番号',
              value: domesticPhoneDisplay(record.emergencyPhone),
              icon: Icons.phone_in_talk_outlined,
              onTap: record.emergencyPhone.trim().isEmpty
                  ? null
                  : () => _callPhone(context, record.emergencyPhone),
            ),
            _actionCard(
              context,
              label: '緊急連絡先住所',
              value: record.emergencyAddress,
              icon: Icons.location_on_outlined,
              onTap: record.emergencyAddress.trim().isEmpty
                  ? null
                  : () => _openGoogleMap(context, record.emergencyAddress),
            ),
            const SizedBox(height: 16),
            if (canViewFamily) ...[
              const Text(
                '家族・扶養情報',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Text('社会保険手続き用・プロフィールの登録内容を表示'),
              const SizedBox(height: 8),
              Text(
                '家族構成：${record.familyComposition.trim().isEmpty ? '未登録' : record.familyComposition}',
              ),
              const SizedBox(height: 8),
              if (record.familyMembers.isEmpty)
                const Text('家族・扶養家族の登録はありません')
              else
                Table(
                  border: TableBorder.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      children: [
                        for (final label in ['氏名', '生年月日', '続柄', '扶養'])
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (final member in record.familyMembers)
                      TableRow(
                        children: [
                          for (final value in [
                            member.name,
                            member.birthDate == null
                                ? '未登録'
                                : '${member.birthDate!.year}/${member.birthDate!.month.toString().padLeft(2, '0')}/${member.birthDate!.day.toString().padLeft(2, '0')}',
                            member.relation,
                            member.isDependent ? 'あり' : 'なし',
                          ])
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(value.isEmpty ? '未登録' : value),
                            ),
                        ],
                      ),
                  ],
                ),
            ],
            if (canManage) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('編集'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _send(context),
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('送信'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _print(context),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('印刷'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonnelPortrait extends StatefulWidget {
  const _PersonnelPortrait({super.key, this.loader});
  final Future<String?> Function()? loader;
  @override
  State<_PersonnelPortrait> createState() => _PersonnelPortraitState();
}

class _PersonnelPortraitState extends State<_PersonnelPortrait> {
  late final Future<String?> _portrait =
      widget.loader?.call() ?? Future.value(null);
  String? _loadedUrl;
  @override
  void dispose(){final url=_loadedUrl;if(url!=null)NetworkImage(url).evict();super.dispose();}
  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 132,
      height: 164,
      child: FutureBuilder<String?>(
        future: _portrait,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          Widget placeholder(String text) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 64),
              Text(text, textAlign: TextAlign.center),
            ],
          );
          if (snapshot.hasError) return placeholder('顔写真を取得できません');
          final url = snapshot.data;
          if (url == null) return placeholder('顔写真未登録');
          _loadedUrl=url;
          return Image.network(
            url,
            fit: BoxFit.contain,
            semanticLabel: '必要書類に登録済みの顔写真',
            errorBuilder: (_, _, _) => placeholder('顔写真を表示できません'),
          );
        },
      ),
    ),
  );
}


class _EmployeePortraitEntry extends StatefulWidget {
  const _EmployeePortraitEntry({super.key, required this.session,
    required this.workerId, required this.loader, required this.registrationBuilder});
  final PersonnelPrivacySession session;
  final String workerId;
  final Future<String?> Function()? loader;
  final Widget Function() registrationBuilder;
  @override State<_EmployeePortraitEntry> createState() => _EmployeePortraitEntryState();
}
class _EmployeePortraitEntryState extends State<_EmployeePortraitEntry> {
  int _revision = 0;
  bool _busy = false;
  bool _allowed(PersonnelPrivacySession session, String worker) =>
    mounted && session.active && !session.revoked &&
    identical(widget.session, session) && widget.workerId == worker &&
    session.snapshot?.canManage == true && session.snapshot!.records.any((row) =>
      row['id'] == worker && row['personnelBasicOnly'] != true);
  Future<void> _open() async {
    if (_busy) return;
    final session = widget.session, worker = widget.workerId;
    final lease = session.epoch;
    setState(() => _busy = true);
    try {
      await session.read(workerIds: {worker});
      session.verify(lease);
      if (!mounted || !_allowed(session, worker)) return;
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PersonnelPrivacyView(session: session, builder: (context, _) {
          if (!_allowed(session, worker)) {
            return const Center(child: Text('対象と管理権限を再確認してください。'));
          }
          return widget.registrationBuilder();
        }),
      ));
      if (saved != true) return;
      await session.read(workerIds: {worker});
      session.verify(lease);
      if (!mounted || !_allowed(session, worker)) return;
      setState(() => _revision++);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('対象と管理権限を再確認してください。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override Widget build(BuildContext context) => Column(children: [
    _PersonnelPortrait(key: ValueKey('employee-portrait:${widget.workerId}:$_revision'), loader: widget.loader),
    OutlinedButton.icon(key: const Key('employee-portrait-register'),
      onPressed: _busy ? null : _open, icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('顔写真を登録・変更')),
  ]);
}
