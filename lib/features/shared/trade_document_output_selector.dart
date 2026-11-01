import 'package:flutter/material.dart';
import 'trade_document_output_layout.dart';

/// Format of the contract front + clauses only; never the financial bundle.
class TradeDocumentOutputSelector extends StatelessWidget {
 const TradeDocumentOutputSelector({super.key,required this.value,required this.onChanged,this.enabled=true});
 final TradeDocumentOutputLayout value;
 final ValueChanged<TradeDocumentOutputLayout> onChanged;
 final bool enabled;
 @override Widget build(BuildContext context)=>DropdownButtonFormField<TradeDocumentOutputLayout>(
  initialValue:value,isExpanded:true,decoration:const InputDecoration(labelText:'注文書・請書の保存・印刷形式',border:OutlineInputBorder(),helperText:'選んだ形式をPDF確認・保存・共有・印刷に使用します。両面はプリンター側でも設定してください。'),
  items:const [
   DropdownMenuItem(value:TradeDocumentOutputLayout.a4TwoPages,child:Text('A4縦・2ページ（帳票＋契約条項）',maxLines:2,overflow:TextOverflow.ellipsis)),
   DropdownMenuItem(value:TradeDocumentOutputLayout.a3Landscape,child:Text('A3横・見開き1枚（2ページを左右に配置）',maxLines:2,overflow:TextOverflow.ellipsis)),
   DropdownMenuItem(value:TradeDocumentOutputLayout.a4Duplex,child:Text('A4 表裏1枚（長辺とじ推奨）')),
  ],onChanged:enabled?(next){if(next!=null)onChanged(next);}:null );
}
