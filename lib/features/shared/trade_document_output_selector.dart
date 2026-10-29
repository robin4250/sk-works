import 'package:flutter/material.dart';
import 'trade_document_output_layout.dart';

/// Format of the contract front + clauses only; never the financial bundle.
class TradeDocumentOutputSelector extends StatelessWidget {
 const TradeDocumentOutputSelector({super.key,required this.value,required this.onChanged,this.enabled=true});
 final TradeDocumentOutputLayout value;
 final ValueChanged<TradeDocumentOutputLayout> onChanged;
 final bool enabled;
 @override Widget build(BuildContext context)=>DropdownButtonFormField<TradeDocumentOutputLayout>(
  initialValue:value,decoration:const InputDecoration(labelText:'注文書・請書の保存・印刷形式',border:OutlineInputBorder(),helperText:'両面はプリンター側の設定も必要です。原本や承認内容は変更しません。'),
  items:const [
   DropdownMenuItem(value:TradeDocumentOutputLayout.a4TwoPages,child:Text('A4縦 2枚（表面・条項）')),
   DropdownMenuItem(value:TradeDocumentOutputLayout.a3Landscape,child:Text('A3横 1枚（表面左・条項右）')),
   DropdownMenuItem(value:TradeDocumentOutputLayout.a4Duplex,child:Text('A4 表裏1枚（長辺とじ推奨）')),
  ],onChanged:enabled?(next){if(next!=null)onChanged(next);}:null );
}
