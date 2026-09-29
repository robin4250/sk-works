import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_connection.dart';

void main() {
  const accepted = CompanyConnection(
    id: 'a-b',
    parentCompanyId: 'company-a',
    childCompanyId: 'company-b',
    status: CompanyConnectionStatus.accepted,
  );

  test('accepted child to parent connection allows upstream transfer', () {
    expect(
      CompanyTransferTargetPolicy.canSendUpstream(
        currentCompanyId: 'company-b',
        targetCompanyId: 'company-a',
        connections: const [accepted],
      ),
      isTrue,
    );
  });

  test('reverse parent to child transfer is not an upstream send', () {
    expect(
      CompanyTransferTargetPolicy.canSendUpstream(
        currentCompanyId: 'company-a',
        targetCompanyId: 'company-b',
        connections: const [accepted],
      ),
      isFalse,
    );
  });

  test('pending or unrelated company cannot be used as transfer target', () {
    const pending = CompanyConnection(
      id: 'b-c',
      parentCompanyId: 'company-b',
      childCompanyId: 'company-c',
      status: CompanyConnectionStatus.pending,
    );

    expect(
      CompanyTransferTargetPolicy.canSendUpstream(
        currentCompanyId: 'company-c',
        targetCompanyId: 'company-b',
        connections: const [pending],
      ),
      isFalse,
    );
    expect(
      CompanyTransferTargetPolicy.canSendUpstream(
        currentCompanyId: 'company-b',
        targetCompanyId: 'company-x',
        connections: const [accepted, pending],
      ),
      isFalse,
    );
  });

  test('company cannot send transfer to itself', () {
    expect(
      CompanyTransferTargetPolicy.canSendUpstream(
        currentCompanyId: 'company-a',
        targetCompanyId: 'company-a',
        connections: const [accepted],
      ),
      isFalse,
    );
  });
}
