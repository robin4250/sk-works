class AppUser {
  const AppUser({
    required this.id,
    required this.companyId,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String companyId;
  final String displayName;
  final UserRole role;
}

enum UserRole { owner, admin, manager, worker, viewer }

abstract interface class AuthRepository {
  Future<AppUser?> currentUser();
  Future<AppUser> signIn({required String email, required String password});
  Future<void> signOut();
}

class EntityRecord {
  const EntityRecord({
    required this.id,
    required this.companyId,
    required this.values,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final Map<String, Object?> values;
  final DateTime createdAt;
  final DateTime updatedAt;
}

abstract interface class CrudRepository {
  Future<List<EntityRecord>> list({required String companyId});
  Future<EntityRecord?> get({
    required String companyId,
    required String id,
  });
  Future<EntityRecord> create({
    required String companyId,
    required Map<String, Object?> values,
  });
  Future<EntityRecord> update({
    required String companyId,
    required String id,
    required Map<String, Object?> values,
  });
  Future<void> delete({
    required String companyId,
    required String id,
  });
}

abstract interface class EmployeeRepository implements CrudRepository {}
abstract interface class PartnerCompanyRepository implements CrudRepository {}
abstract interface class WorkerRepository implements CrudRepository {}
abstract interface class QualificationRepository implements CrudRepository {}
abstract interface class SiteRepository implements CrudRepository {}
abstract interface class AttendanceRepository implements CrudRepository {}
abstract interface class InvoiceRepository implements CrudRepository {}

class AppRepositories {
  const AppRepositories({
    required this.auth,
    required this.employees,
    required this.partnerCompanies,
    required this.workers,
    required this.qualifications,
    required this.sites,
    required this.attendance,
    required this.invoices,
  });

  final AuthRepository auth;
  final EmployeeRepository employees;
  final PartnerCompanyRepository partnerCompanies;
  final WorkerRepository workers;
  final QualificationRepository qualifications;
  final SiteRepository sites;
  final AttendanceRepository attendance;
  final InvoiceRepository invoices;
}
