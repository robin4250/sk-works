import 'dart:async';
import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'chat_cloud_repository.dart';
import 'line_talk_page.dart';
import 'line_linked_talk_page.dart';

class LineJoinedGroupsPage extends StatefulWidget {
  const LineJoinedGroupsPage({super.key, this.targetGroupId, this.selectOnly = false, this.newGroupCompanyId});
  final String? targetGroupId;
  final bool selectOnly;
  final String? newGroupCompanyId;
  @override
  State<LineJoinedGroupsPage> createState() => _LineJoinedGroupsPageState();
}
class _LineJoinedGroupsPageState extends State<LineJoinedGroupsPage> with WidgetsBindingObserver {
  final _repository = ChatCloudRepository.maybeCreate();
  List<Map<String,dynamic>> _rows = const [];
  String? _error, _actor;
  bool _loading = true, _busy = false, _master = false, _foreground = true;
  int _generation = 0;
  Timer? _timer;
  String _tr(String value) => SkoLanguageController.tr(value);
  @override
  void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); _load();
    _timer=Timer.periodic(const Duration(seconds:30), (_) {
      if (mounted && _foreground && !_busy && (ModalRoute.of(context)?.isCurrent ?? false)) _load();
    });
  }
  @override
  void dispose() { _generation++; _timer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground=state==AppLifecycleState.resumed;
    if(_foreground) _load();
  }
  Future<void> _load() async {
    final repository=_repository;
    final actor=repository?.currentUserId;
    final generation=++_generation;
    if(actor!=_actor && mounted) setState(() { _rows=const []; _actor=actor; _master=false; });
    if(repository==null || actor==null) {
      if(mounted) setState(() { _loading=false; _error='SKOへのログインが必要です。'; }); return;
    }
    try {
      final master=await repository.canRefreshLineDirectory();
      final rows=await repository.loadJoinedLineGroups(targetGroupId:widget.targetGroupId,newGroupCompanyId:widget.newGroupCompanyId);
      if(!mounted || generation!=_generation || repository.currentUserId!=actor) return;
      setState(() { _rows=rows; _master=master; _loading=false; _error=null; });
    } catch(_) {
      if(mounted && generation==_generation) setState(() {
        if(repository.currentUserId!=actor) _rows=const [];
        _loading=false; _error='参加グループを読み込めませんでした。再読み込みしてください。';
      });
    }
  }
  Future<void> _refresh() async {
    if(_busy) return;
    setState(()=>_busy=true);
    try { if(_master) await _repository?.refreshLineDirectory(); await _load(); }
    catch(_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_tr('参加状況を更新できませんでした。保存済みの一覧を表示します。'))));
      await _load();
    } finally { if(mounted) setState(()=>_busy=false); }
  }
  void _help() => showDialog<void>(context:context,builder:(context)=>AlertDialog(
    title:Text(_tr('参加済みグループ一覧')),
    content:SingleChildScrollView(child:Text(_tr('公式アカウントの参加・投稿を受信したグループが自動で追加されます。以前の受信記録があるグループは再読み込みで参加状況を確認できます。受信記録のない参加済みグループは、次の投稿を受信すると追加されます。未連携の一覧はマスターのみ確認できます。LINEへの送信や過去投稿の自動取得は行いません。'))),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:Text(_tr('閉じる')))]));
  Future<void> _select(Map<String,dynamic> row) async {
    try { await _selectSource(row); } catch(_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_tr('LINEトークを追加できませんでした。権限と連携先を再確認してください。'))));
      await _load();
    }
  }
  Future<void> _selectSource(Map<String,dynamic> row) async {
    final repository=_repository;
    final actor=repository?.currentUserId;
    if(repository==null || actor==null || actor!=_actor) { await _load(); return; }
    if(row['linked']==true || (widget.targetGroupId==null && !widget.selectOnly)) {
      // Reload the permission-scoped directory before opening a saved source.
      final current=await repository.loadJoinedLineGroups(targetGroupId:widget.targetGroupId,newGroupCompanyId:widget.newGroupCompanyId);
      final matching=current.where((value)=>value['id']==row['id']);
      if(!mounted || repository.currentUserId!=actor || matching.length!=1) return;
      final value=matching.single;
      final target=value['read_target_group_id']?.toString();
      if(target!=null) {
        await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>LineLinkedTalkPage(targetGroupId:target,directoryId:value['id'].toString(),name:value['display_name']?.toString()??_tr('グループ名未取得'))));
        return;
      }
      final primary=value['primary_group_id']?.toString();
      if(primary!=null) await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>LineTalkPage(initialGroupId:primary)));
      return;
    }
    if(widget.selectOnly) {
      if(row['can_select']==true) Navigator.pop(context,row);
      return;
    }
    final group=widget.targetGroupId;
    if(group==null || row['can_link']!=true) return;
    final companyName=await repository.lineLinkCompanyName();
    if(!mounted || repository.currentUserId!=actor) return;
    final confirm=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:Text(_tr('LINEトークを追加しますか？')),
      content:Text('$companyName\n${row['display_name'] ?? _tr('グループ名未取得')}\n${_tr('このSKOグループから、LINEグループ名を押して受信トークを開けるようにします。会社への連携先を確認して追加してください。')}'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:Text(_tr('戻る'))),FilledButton(onPressed:()=>Navigator.pop(context,true),child:Text(_tr('追加')))]));
    if(confirm!=true || !mounted || repository.currentUserId!=actor) return;
    setState(()=>_busy=true);
    try { await repository.linkLineSource(group,row['id'].toString());
      if(mounted && repository.currentUserId==actor) Navigator.pop(context,row);
    } catch(_) {
      if(mounted) { setState(()=>_busy=false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(_tr('LINEトークを追加できませんでした。権限と連携先を再確認してください。')))); await _load(); }
    }
  }
  String _status(Map<String,dynamic> row) => row['joined']==true
    ? row['linked']==true ? '追加済み' : '参加中'
    : row['joined']==false ? '参加なし' : '参加状況未確認';
  bool _enabled(Map<String,dynamic> row) => widget.selectOnly ? row['can_select']==true
    : row['linked']==true || widget.targetGroupId==null ? row['primary_group_id']!=null : row['can_link']==true;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_tr(widget.targetGroupId==null ? '参加済みグループ一覧' : 'LINEトークを追加')),
      actions:[IconButton(onPressed:_help,icon:const Icon(Icons.help_outline),tooltip:_tr('使い方')),IconButton(onPressed:_busy?null:_refresh,icon:const Icon(Icons.refresh),tooltip:_tr('再読み込み'))]),
    body:Column(children:[
      if(_busy) const LinearProgressIndicator(),
      Expanded(child:_loading ? const Center(child:CircularProgressIndicator())
        : _error!=null ? Center(child:Padding(padding:const EdgeInsets.all(16),child:Text(_tr(_error!))))
        : _rows.isEmpty ? Center(child:Padding(padding:const EdgeInsets.all(16),child:Text(_tr('確認できる参加グループはまだありません。'))))
        : ListView.separated(itemCount:_rows.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,index){
          final row=_rows[index];
          return ListTile(leading:const Icon(Icons.groups_outlined),title:Text(row['display_name']?.toString() ?? _tr('グループ名未取得')),
            subtitle:Text(_tr(_status(row))),trailing:_enabled(row)?const Icon(Icons.chevron_right):null,onTap:_busy||!_enabled(row)?null:()=>_select(row));
        })),
    ]));
}
