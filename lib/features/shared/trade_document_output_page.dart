import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import '../../domain/trade_document_terms_snapshot.dart';
import 'trade_document_form_renderer.dart';
import 'trade_document_output_layout.dart';
import 'trade_document_output_selector.dart';
import 'standalone_trade_document_print_scope.dart';
import 'financial_preview_chrome.dart';
import 'pdf_pinch_pages.dart';

/// Authorized form-only derivative. Parent financial pages are a separate output.
class TradeDocumentOutputPage extends StatefulWidget {
 const TradeDocumentOutputPage({super.key,required this.payload,required this.canonicalBytes,required this.requireScope,this.scopeChanges,this.onNativeOutputChanged});
 final Map<String,dynamic> payload;
 final Uint8List canonicalBytes;
 final VoidCallback requireScope;
 final Listenable? scopeChanges;
 final ValueChanged<bool>? onNativeOutputChanged;
 @override State<TradeDocumentOutputPage> createState()=>_OutputState();
}
class _OutputState extends State<TradeDocumentOutputPage> with WidgetsBindingObserver {
 late final Map<String,dynamic> _payload;
 late final Uint8List _canonical;
 late final StandaloneTradeDocumentPrintScope _print;
 Uint8List? _bytes;bool _busy=false,_revoked=false;int _epoch=0;String? _error;
 TradeDocumentOutputLayout _layout=TradeDocumentOutputLayout.a4TwoPages;
 bool get _known=>_payload.containsKey('contract_terms');
 void _verify(){if(!mounted||_revoked)throw StateError('書類を開き直してください。');try{widget.requireScope();}catch(_){_retire();rethrow;}}
 @override void initState(){super.initState();
  _payload=Map<String,dynamic>.from(jsonDecode(jsonEncode(widget.payload)) as Map);
  _canonical=Uint8List.fromList(widget.canonicalBytes);_bytes=_canonical;
  if(_known)TradeDocumentTermsSnapshot.fromJson(_payload['contract_terms']);
  _print=StandaloneTradeDocumentPrintScope(verifyScope:_verify,currentBytes:()=>_bytes,currentTarget:()=>_layout,onRevoke:_retire);
  widget.scopeChanges?.addListener(_scopeChanged);WidgetsBinding.instance.addObserver(this);
  if(WidgetsBinding.instance.lifecycleState!=AppLifecycleState.resumed)_retire();
 }
 void _scopeChanged(){try{_verify();}catch(_){_retire();}}
 void _retire(){if(_revoked)return;_revoked=true;_busy=false;_bytes=null;_epoch++;_print.invalidate();if(mounted)setState(()=>_error='書類の閲覧状態が変わりました。開き直してください。');}
 @override void didUpdateWidget(covariant TradeDocumentOutputPage old){super.didUpdateWidget(old);if(!identical(old.scopeChanges,widget.scopeChanges))old.scopeChanges?.removeListener(_scopeChanged);if(!identical(old.canonicalBytes,widget.canonicalBytes)||!identical(old.payload,widget.payload)||!identical(old.scopeChanges,widget.scopeChanges))_retire();}
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  try{_print.visibilityChanged(switch(state){AppLifecycleState.resumed=>StandalonePrintVisibility.resumed,AppLifecycleState.inactive=>StandalonePrintVisibility.inactive,AppLifecycleState.hidden=>StandalonePrintVisibility.hidden,AppLifecycleState.paused=>StandalonePrintVisibility.paused,AppLifecycleState.detached=>StandalonePrintVisibility.detached});}catch(_){_retire();}
 }
 Future<void> _choose(TradeDocumentOutputLayout next)async{
  if(_busy||_revoked)return;final epoch=++_epoch;setState(()=>_busy=true);
  try{_verify();final bytes=await TradeDocumentFormRenderer.output(_payload,layout:next,canonicalBytes:_canonical);_verify();if(epoch==_epoch)setState((){_bytes=bytes;_layout=next;});}
  catch(error){if(mounted&&!_revoked)setState(()=>_error=error.toString());}
  finally{if(mounted&&epoch==_epoch)setState(()=>_busy=false);}
 }
 Future<void> _output({bool share=false})async{
  final bytes=_bytes;if(_busy||bytes==null||_revoked)return;setState(()=>_busy=true);
  try{_verify();_print.begin(bytes);widget.onNativeOutputChanged?.call(true);final name=_payload['kind']=='order'?'注文書.pdf':'請書.pdf';
   if(share){_print.layout();await Printing.sharePdf(bytes:bytes,filename:name);}
   else{await Printing.layoutPdf(name:name,format:_layout==TradeDocumentOutputLayout.a3Landscape?PdfPageFormat.a3.landscape:PdfPageFormat.a4,onLayout:(_)async=>_print.layout());}
   _verify();
  }catch(error){if(mounted&&!_revoked)setState(()=>_error='保存・印刷の結果を確認してください。');}
  finally{_print.end();widget.onNativeOutputChanged?.call(false);if(mounted)setState(()=>_busy=false);}
 }
 @override void dispose(){widget.scopeChanges?.removeListener(_scopeChanged);WidgetsBinding.instance.removeObserver(this);_revoked=true;_bytes=null;_epoch++;_print.invalidate();super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(_payload['kind']=='order'?'注文書を保存・印刷':'請書を保存・印刷')),
  body:FinancialPreviewChrome(
   status:[
    if(_error!=null)Text(_error!),
    if(!_revoked&&!_known)const Text('保存された原本の形式を保持します。過去書類に新しい条項は追加しません。'),
    if(_busy)const LinearProgressIndicator(),
   ],
   actions:[
    if(!_revoked&&_known)SizedBox(width:MediaQuery.sizeOf(context).width-24,
      child:Theme(data:Theme.of(context).copyWith(inputDecorationTheme:const InputDecorationTheme(
        isDense:true,contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:8),
        labelStyle:TextStyle(fontSize:12),helperStyle:TextStyle(fontSize:11))),
        child:TradeDocumentOutputSelector(key:ValueKey(_layout),value:_layout,enabled:!_busy,onChanged:_choose))),
   ],
   preview:!_revoked&&_bytes!=null?PdfPreview.builder(
     pagesBuilder:(context,pages)=>PdfPinchPages(pages:pages),
     build:(_)async{_verify();return _bytes!;},canChangePageFormat:false,canChangeOrientation:false,
     useActions:false,allowPrinting:false,allowSharing:false):const SizedBox.shrink(),
   footer:!_revoked?Row(children:[
    Expanded(child:OutlinedButton(onPressed:_busy?null:()=>_output(),
      style:OutlinedButton.styleFrom(minimumSize:const Size(0,48),textStyle:const TextStyle(fontSize:14)),child:const Text('印刷'))),
    const SizedBox(width:10),
    Expanded(child:FilledButton(onPressed:_busy?null:()=>_output(share:true),
      style:FilledButton.styleFrom(minimumSize:const Size(0,48),textStyle:const TextStyle(fontSize:14)),child:const Text('保存・共有'))),
   ]):const SizedBox.shrink(),
  ));
}
