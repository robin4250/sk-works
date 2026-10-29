import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../domain/company_seal_snapshot.dart';
import '../../domain/partner_company_bank_account.dart';
import '../../domain/trade_document_form_draft.dart';
import 'company_seal_pdf.dart';
import 'trade_document_form_geometry.dart';

/// Approved new form front. Missing structured entries remain blank; no inference.
/// Existing saved documents without a terms marker never enter this renderer.
class TradeDocumentFormPdf {
 const TradeDocumentFormPdf._();
 static DateTime _date(Object? value){final raw=value?.toString()??'',d=DateTime.tryParse(raw);if(!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)||d==null||d.toIso8601String().substring(0,10)!=raw)throw StateError('契約日を確認できません。');return d;}
 static String _fullDate(Object? value){final d=_date(value);return '${d.year}年${d.month}月${d.day}日';}
 static Future<void> append(pw.Document document,Map<String,dynamic> p,
  {required pw.Font regularFont,required pw.Font boldFont})async {
  final canvas=await buildCanvas(p,regularFont:regularFont,boldFont:boldFont);
  document.addPage(pw.Page(pageFormat:PdfPageFormat.a4,margin:pw.EdgeInsets.zero,build:(_)=>canvas));
 }
 static Future<pw.Widget> buildCanvas(Map<String,dynamic> p,
  {required pw.Font regularFont,required pw.Font boldFont})async {
  if(!const ['order','acceptance'].contains(p['kind']))throw StateError('契約書類の種類を確認できません。');
  final order=p['kind']=='order',g=tradeDocumentFormGeometry[p['kind']=='order'?'order':'acceptance']!;
  final ys=(g['ys'] as List).cast<num>().map((n)=>n.toDouble()).toList(),cols=(g['grid_columns'] as List).cast<num>().map((n)=>n.toDouble()).toList();
  const left=34.0;final right=PdfPageFormat.a4.width-34,width=right-left,height=PdfPageFormat.a4.height,top=ys[0];
  final scale=width/(order?1217:1183);
  double x(double px)=>left+(px-(order?164:239))*scale;
  double hy(double py)=>top+((order?532:499)-py)*(order?scale:0.35);
  final parts=<pw.Widget>[];
  final fields=p.containsKey('form_fields')?TradeDocumentFormFields.fromJson(p['form_fields']).toJson():null;
  void line(double x1,double y1,double x2,double y2,{double stroke=0.5}) {
   parts.add(pw.Positioned(left:x1,top:height-y1,child:pw.SizedBox(width:x2==x1?stroke:x2-x1,height:y1==y2?stroke:y1-y2,
    child:pw.Container(color:PdfColors.black))));
  }
  void text(String value,double x1,double y1,double w,double h,{double size=8,bool center=false,bool bold=false}) {
   if(value.isEmpty)return;
   parts.add(pw.Positioned(left:x1,top:height-y1-h,child:pw.SizedBox(width:w,height:h,child:pw.FittedBox(fit:pw.BoxFit.scaleDown,
    alignment:center?pw.Alignment.center:pw.Alignment.centerLeft,child:pw.SizedBox(width:w,child:pw.Text(value,
     textAlign:center?pw.TextAlign.center:pw.TextAlign.left,style:pw.TextStyle(font:bold?boldFont:regularFont,fontSize:size)))))));
  }
  void label(String value,double x1,double x2,double high,double low,{double size=8})=>text(value,x1+2,low+2,x2-x1-4,high-low-4,size:size,center:true,bold:true);
  String val(Object? value)=>value?.toString()??'';
  String money(Object? value){if(value is! int||value<0)throw StateError('契約金額を確認できません。');return value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'),(_)=>',');}
  void date(Object? raw,double xx,double low,double high,{bool labelEra=true}) {
   if(raw==null)return;final d=_date(raw);
   final reiwa=!d.isBefore(DateTime(2019,5,1));final year=reiwa?d.year-2018:d.year;
   text('${labelEra?(reiwa?'令和':'西暦'):''}$year 年 ${d.month} 月 ${d.day} 日',xx,low, right-xx-3,high-low,size:7.5);
  }
  final issuer=Map<String,dynamic>.from(p['issuer'] as Map),counter=Map<String,dynamic>.from(p['counterparty'] as Map);
  final glyphs=order?'注文書':'請書',gap=order?23.0:28.0;final titleWidth=glyphs.length*15+(glyphs.length-1)*gap;
  for(var index=0;index<glyphs.length;index++){text(glyphs[index],(PdfPageFormat.a4.width-titleWidth)/2+index*(15+gap),height-(order?70:48),15,24,size:15,bold:true);}
  date(p['issue_date'],right-130,height-50,height-34);
  final partyY=hy(order?250:217),recipientY=hy(order?290:270);
  text(order?'（受注者）':'（注文者）',left+5,partyY-3,width*.4,14,size:8.5,bold:true);
  text(val(counter['name']),left+2,recipientY-4,width*.35,20,size:10,bold:true);text('殿',left+width*.355,recipientY-4,18,20,size:9);
  text(order?'下記の通り注文致しますので、工事請負契約条項及び':'工事請負契約条項及び下記事項を承諾のうえ、貴注文',left+2,hy(order?365:330)-3,width*.49,14,size:7.6,bold:true);
  text(order?'下記事項をご確認のうえ請書を提出して下さい。':'をお請け致します。',left+2,hy(order?400:365)-3,width*.49,14,size:7.6,bold:true);
  final rx=left+width*.535,vx=rx+40;
  text(order?'（注文者）':'（受注者）',rx,hy(order?272:272)-3,right-rx,14,size:8.5,bold:true);
  final seal=CompanySealSnapshot.fromJson(p['company_seal_snapshot']);
  final sealOn=p['company_seal_enabled']==true&&seal.name.isNotEmpty;
  if(sealOn&&seal.name!=val(issuer['name']))throw StateError('自社名と登録角印の会社が一致しません。');
  final sealFont=sealOn?await CompanySealPdf.loadStyleFont(seal.style):regularFont;
  for(final row in [
   ('住所','address',order?338.0:319.0,order?367.0:344.0),
   ('会社名','name',order?406.0:382.0,order?435.0:411.0),
   ('ＴＥＬ','phone',order?459.0:437.0,order?472.0:448.0),
   ('ＦＡＸ','fax',order?495.0:478.0,order?508.0:489.0),
  ]){
   final yy=hy(row.$3),bb=hy(row.$4);text(row.$1,rx,yy-3,38,14,size:8,bold:true);
   if(row.$2=='name'){
    // The complete company name and its own saved seal share a bounded row.
    // Place the seal center at the measured right edge; never at the page edge.
    parts.add(pw.Positioned(left:vx,top:height-bb-23,child:pw.SizedBox(width:right-vx-3,height:23,child:pw.LayoutBuilder(builder:(context,constraints){
     final available=constraints!.maxWidth,registered=val(issuer['name']);
     final natural=boldFont.getFont(context).stringMetrics(registered).advanceWidth;
     final maxText=available-(sealOn?11:0);
     final fontSize=natural==0?7.5:(maxText/natural).clamp(0.1,7.5).toDouble();
     final printedWidth=natural*fontSize,sealLeft=(printedWidth-11).clamp(0.0,available-22).toDouble();
     return pw.Stack(children:[
      pw.Positioned(left:0,top:0,child:pw.SizedBox(width:maxText,height:23,child:pw.Align(alignment:pw.Alignment.centerLeft,child:pw.Text(registered,style:pw.TextStyle(font:boldFont,fontSize:fontSize))))),
      if(sealOn)pw.Positioned(left:sealLeft,top:0.5,child:pw.SizedBox(width:22,height:22,child:CompanySealPdf.build(seal.name,font:sealFont,fallbackFont:regularFont,companyId:seal.companyId,uploadedPng:seal.uploadedPng,style:seal.style,size:22))),
     ]);
    }))));
   }else{text(val(issuer[row.$2]),vx,bb+1,right-vx-3,row.$2=='address'?24:14,size:8);}
   line(vx-2,bb,right,bb,stroke:0.3);
  }
  for(var i=0;i<ys.length;i++){if(i==4||i==5)continue;line(left,ys[i],right,ys[i],stroke:[0,9,20,21].contains(i)?0.9:0.5);}
  line(left,top,left,ys.last,stroke:0.9);line(right,top,right,ys.last,stroke:0.9);
  final a=x(order?301:377),m=x(order?810:876),n=x(order?984:1046);
  for(final xx in [a,m,n]){line(xx,ys[0],xx,ys[2]);}
  label('工 事 名 称',left,a,ys[0],ys[1]);text(val(p['work_name']),a+3,ys[1]+3,m-a-6,ys[0]-ys[1]-6,size:9);
  label('工 事 内 容',m,n,ys[0],ys[1]);
  if(fields!=null)text(fields['work_content'] as String,n+3,ys[1]+3,right-n-6,ys[0]-ys[1]-6,size:8);
  label('工 事 場 所',left,a,ys[1],ys[2]);text(val(p['work_address']),a+3,ys[2]+3,m-a-6,ys[1]-ys[2]-6,size:8);
  label('工　　期',m,n,ys[1],ys[2]);final mid=(ys[1]+ys[2])/2;line(n,mid,right,mid);
  for(final r in [('着手','period_start',mid,ys[1]),('完成','period_end',ys[2],mid)]){
   text(r.$1,n+4,r.$3+1,26,r.$4-r.$3-2,size:7.5);date(p[r.$2],n+30,r.$3+1,r.$4-1);
  }
  line(a,ys[2],a,ys[3]);label('発 注 金 額',left,a,ys[2],ys[3]);
  if(p['total_amount_yen']!=null)text('金 ${money(p['total_amount_yen'])} 円',a+3,ys[3]+3,width*.34,ys[2]-ys[3]-6,size:9);
  text('下記「施工単価内訳書」による',left+width*.45,ys[3]+3,width*.5,ys[2]-ys[3]-6,size:7.5);
  final spine=x(order?210:285),choice=x(order?465:536),when=x(order?595:663),paylabel=x(order?882:945);
  for(final xx in [spine,a,choice,when,paylabel,n]){line(xx,ys[3],xx,ys[6]);}
  final cy=(ys[3]+ys[6])/2;
  for(var i=0;i<4;i++){text('支払方法'[i],left+1,cy+18-i*14,spine-left-2,13,size:8.4,center:true,bold:true);}
  for(var i=0;i<3;i++){
   final high=ys[3+i],low=ys[4+i];if(i<2)line(spine,low,right,low);
   label(['前金払','部分払','完成払'][i],spine,a,high,low);
   label('有　・　無',a,choice,high,low,size:8.5);label('支払時期',choice,when,high,low);
   label(i<2?'支 払 額':'支　払',paylabel,n,high,low);
   if(fields!=null){
    final payment=(fields['payments'] as Map)[['advance','partial','completion'][i]] as Map;
    if(payment['choice']!='unspecified'){
     final center=a+(choice-a)*(payment['choice']=='yes'?.28:.75);
     parts.add(pw.Positioned(left:center-7,top:height-(high+low)/2-7,child:pw.Container(width:14,height:14,decoration:pw.BoxDecoration(shape:pw.BoxShape.circle,border:pw.Border.all(width:.6)))));
    }
    date(payment['date'],when+3,low+2,high-2);
    if(payment['amount_yen']!=null)text('${money(payment['amount_yen'])} 円',n+3,low+2,right-n-6,high-low-4,size:8);
   }
  }
  for(final xx in [a,choice,when,m,n]){line(xx,ys[6],xx,ys[8]);}
  label('出来高締切日',left,a,ys[6],ys[7],size:7.8);label('請求書締切日',choice,when,ys[6],ys[7],size:7.8);label('支　払　日',m,n,ys[6],ys[7]);
  for(final r in [(a,choice),(when,m)]){text('毎月',r.$1+7,ys[7]+3,26,ys[6]-ys[7]-6,size:8);text('日',r.$2-12,ys[7]+3,10,ys[6]-ys[7]-6,size:8);}
  final offset=fields?['payment_month_offset'];
  final months=[for(var i=0;i<3;i++)offset==i?'【${['当月','翌月','翌々月'][i]}】':['当月','翌月','翌々月'][i]].join(' ・ ');
  text('（ $months ）',n+3,ys[7]+3,right-n-18,ys[6]-ys[7]-6,size:7.2);text('日',right-12,ys[7]+3,10,ys[6]-ys[7]-6,size:8);
  label('支 払 条 件',left,a,ys[7],ys[8]);label('現金比率',a,choice,ys[7],ys[8]);label('手形比率',when,m,ys[7],ys[8]);
  text('（手形決済日：支払日より　　　ヶ月）',n+5,ys[8]+3,right-n-8,ys[7]-ys[8]-6,size:7);
  line(a,ys[8],a,ys[9]);label('支　給　品',left,a,ys[8],ys[9]);
  if(fields!=null){
   for(final row in [('progress_cutoff_day',a+35,choice-14),('invoice_cutoff_day',when+35,m-14),('payment_day',right-29,right-14)]){
    text(val(fields[row.$1]),row.$2,ys[7]+3,row.$3-row.$2,ys[6]-ys[7]-6,size:8,center:true);
   }
   if(fields['cash_ratio_percent']!=null)text('${fields['cash_ratio_percent']} %',choice+3,ys[8]+3,when-choice-6,ys[7]-ys[8]-6,size:8,center:true);
   if(fields['bill_ratio_percent']!=null)text('${fields['bill_ratio_percent']} %',m+3,ys[8]+3,n-m-6,ys[7]-ys[8]-6,size:8,center:true);
   if(fields['bill_months']!=null)text('${fields['bill_months']}',right-51,ys[8]+3,15,ys[7]-ys[8]-6,size:8,center:true);
   text(fields['supplies'] as String,a+3,ys[9]+3,right-a-6,ys[8]-ys[9]-6,size:8);
  }
  label(order?'施　工　単　価　内　訳　書':'工　事　費　内　訳　書',left,right,ys[9],ys[10],size:10);
  for(final xx in cols.skip(1).take(5)){line(xx,ys[10],xx,ys[20]);}
  for(var i=0;i<6;i++){label(['項　　　目','数　量','単位','単　価','金　額','備　　　考'][i],cols[i],cols[i+1],ys[10],ys[11],size:8.5);}
  if(fields!=null){
   final rows=fields['rows'] as List;
   for(var row=0;row<9;row++){
    final values=rows[row] as Map;
    for(var col=0;col<6;col++){
     final key=['item','quantity','unit','unit_price_yen','amount_yen','note'][col];
     final value=values[key];
     text(value==null?'':(key.endsWith('_yen')?money(value):val(value)),cols[col]+2,ys[12+row]+2,cols[col+1]-cols[col]-4,ys[11+row]-ys[12+row]-4,size:7.5,center:col>0&&col<5);
    }
   }
  }
  text('［特記事項］（右記工事請負契約条項に記載されていない事項を記入）',left+3,ys[20]-13,width-6,12,size:7.4,bold:true);
  final bank=order&&p['counterparty_bank']!=null?PartnerCompanyBankAccount.fromJson(p['counterparty_bank']):null;
  final details=[
   if(p['intro_text']?.toString().trim().isNotEmpty==true)val(p['intro_text']),
   if(!order&&p['acceptance_text']?.toString().trim().isNotEmpty==true)val(p['acceptance_text']),
   '支払条件：${val(p['payment_conditions'])}',
   if(p['tax_amount_yen']!=null)'うち消費税等：${money(p['tax_amount_yen'])} 円',
   if(bank!=null)'受注者の振込先：${bank.display}',
   if(p['notes']?.toString().trim().isNotEmpty==true)'特記：${val(p['notes'])}',
   '対象月：${val(p['month'])} 月分　発行日：${val(p['issue_date'])}　注文日：${val(p['order_date'])}',
   if(!order)'承諾日：${_fullDate(p['issue_date'])}',
   '自社法人番号：${val(issuer['corporate_number'])}　相手法人番号：${val(counter['corporate_number'])}',
   '自社代表者名：${val(issuer['representative_name'])}',
   if(!sealOn)'角印：無印',
   '相手住所：${val(counter['address'])}　相手代表者名：${val(counter['representative_name'])}',
  ].join('\n');
  text(details,left+4,ys.last+4,width-8,ys[20]-ys.last-19,size:8);
  return pw.Stack(children:parts);
 }
}
