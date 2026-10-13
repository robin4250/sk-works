import 'dart:async';
import 'package:flutter/material.dart';
import '../../international/language_controller.dart';
import 'chat_cloud_repository.dart';
class LineLinkedTalkPage extends StatefulWidget {
 const LineLinkedTalkPage({super.key,required this.targetGroupId,required this.directoryId,required this.name});
 final String targetGroupId,directoryId,name;
 @override
 State<LineLinkedTalkPage> createState()=>_LineLinkedTalkPageState();
}
class _LineLinkedTalkPageState extends State<LineLinkedTalkPage> with WidgetsBindingObserver {
 final _repository=ChatCloudRepository.maybeCreate();
 List<Map<String,dynamic>> _rows=const [];
 String? _error;
 bool _loading=true,_foreground=true;
 int _generation=0;
 Timer? _timer;
 @override
 void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_load();_timer=Timer.periodic(const Duration(seconds:30),(_){if(mounted && _foreground && (ModalRoute.of(context)?.isCurrent??false))_load();});}
 @override
 void dispose(){_generation++;_timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
 @override
 void didChangeAppLifecycleState(AppLifecycleState state){_foreground=state==AppLifecycleState.resumed;if(_foreground)_load();}
 Future<void> _load() async {
  final generation=++_generation,repository=_repository;
  final actor=repository?.currentUserId;
  try{
   if(repository==null||actor==null)throw StateError('login');
   final rows=await repository.loadLinkedLineMessages(widget.targetGroupId,widget.directoryId);
   if(!mounted||generation!=_generation||repository.currentUserId!=actor)return;
   setState((){_rows=rows;_error=null;_loading=false;});
  }catch(_){if(mounted&&generation==_generation)setState((){_rows=const [];_loading=false;_error='受信トークを読み込めませんでした。再読み込みしてください。';});}
 }
 @override
 Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.name),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh),tooltip:SkoLanguageController.tr('再読み込み'))]),body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Padding(padding:const EdgeInsets.all(16),child:Text(SkoLanguageController.tr(_error!)))):_rows.isEmpty?Center(child:Text(SkoLanguageController.tr('このグループの受信テキストはまだありません。'))):ListView.separated(padding:const EdgeInsets.all(16),itemCount:_rows.length,separatorBuilder:(_,__)=>const SizedBox(height:12),itemBuilder:(context,index){final row=_rows[index];final at=DateTime.tryParse(row['sent_at']?.toString()??'')?.toLocal();return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${row['sender_display_name']??'LINE'}${at==null?'':'  ${at.year}/${at.month}/${at.day} ${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}'}',style:Theme.of(context).textTheme.labelMedium),const SizedBox(height:8),SelectableText(row['body']?.toString()??'')]))); }));
}
