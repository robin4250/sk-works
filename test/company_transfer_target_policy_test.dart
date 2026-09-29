import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/company_connection.dart';

void main() {
  const accepted = CompanyConnection(
    id: 'a-b',
    companyAId: 'company-a',
    companyBId: 'company-b',
    status: CompanyConnectionStatus.accepted,
  );

  test('accepted connection allows transfer to the connected company', () {
    expect(
      CompanyTransferTargetPolicy.canSend(
        currentCompanyId: 'company-b',
        targetCompanyId: 'company-a',
        connections: const [accepted],
      ),
      isTrue,
    );
  });

  test('pending or unrelated company cannot be used as transfer target', () {
    const pending = CompanyConnection(
      id: 'b-c',
      companyAId: 'company-b',
      companyBId: 'company-c',
      status: CompanyConnectionStatus.pending,
    );

    expect(
      CompanyTransferTargetPolicy.canSend(
        currentCompanyId: 'company-b',
        targetCompanyId: 'company-c',
        connections: const [pending],
      ),
      isFalse,
    );
    expect(
      CompanyTransferTargetPolicy.canSend(
        currentCompanyId: 'company-b',
        targetCompanyId: 'company-x',
        connections: const [accepted, pending],
      ),
      isFalse,
    );
  });

  test('company cannot send transfer to itself', () {
    expect(
      CompanyTransferTargetPolicy.canSend(
        currentCompanyId: 'company-a',
        targetCompanyId: 'company-a',
        connections: const [accepted],
      ),
      isFalse,
    );
  });
}
