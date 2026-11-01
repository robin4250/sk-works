import 'dart:convert';
import 'package:http/http.dart' as http;

// Explicit backend support for existing positive workflow fixtures only.
// Production has no such RPC until the site backend is fully qualified.
http.StreamedResponse supportedSiteWorkflowCapability(http.BaseRequest request,
    {required Object? actor, required Object? company, required Object? session,
    Object? role = 'manager'}) => http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({
      'contract_version': 1, 'workflow_contract_version': 1, 'actor_id': actor,
      'session_id': session, 'company_id': company, 'role': role,
      'master_enabled': true, 'can_read': true, 'can_create': true, 'can_mutate': true,
    }))), 200, headers: {'content-type': 'application/json'}, request: request);
