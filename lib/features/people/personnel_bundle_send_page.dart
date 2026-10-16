import 'package:flutter/material.dart';

import 'company_transfer_send_page.dart';
import 'people_cloud_repository.dart';

class PersonnelBundleSendPage extends StatelessWidget {
  const PersonnelBundleSendPage({
    super.key,
    required this.workerIds,
    this.privacySession,
  });

  final Set<String> workerIds;
  final PersonnelPrivacySession? privacySession;

  @override
  Widget build(BuildContext context) {
    final session=privacySession;
    if(session!=null)return PersonnelPrivacyView(session:session,builder:(context,_)=>session.snapshot?.canManage==true?_page(session):const Center(child:Text('送信権限を確認できません。')));
    return _page(null);
  }
  Widget _page(PersonnelPrivacySession? session){
    Future<void> authorize() async {
      if(session==null)return;
      await session.read(forExport:true,workerIds:workerIds);
      final lease=session.epoch;
      final repository=PeopleCloudRepository.maybeCreate();
      if(repository==null)throw const PersonnelScopeChanged();
      // Existing delivery RPCs select the default company. Never send another
      // company's data through that legacy route when viewing an explicit scope.
      if((await repository.membership()).companyId!=session.company)throw const PersonnelScopeChanged();
      session.verify(lease);
    }
    return CompanyTransferSendPage(
      scopeChanges:session,
      scopeAllowed:session==null?null:()=>session.active&&!session.revoked&&session.snapshot?.canManage==true,
      beforeLoad:session==null?null:authorize,
      beforeSend:session==null?null:authorize,
      title: '社員データを送信',
      sourceKind: 'worker_personnel',
      subjectLabel: '社員',
      workerIds: workerIds,
      description: '社員の基本情報・資格・必要書類を一式で送信します。出所会社情報も保持します。',
    );
  }
}
