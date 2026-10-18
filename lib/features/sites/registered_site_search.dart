import 'site_page.dart';

/// Filters only the records already loaded by the existing site repository.
/// A registered site ID is the local SiteRecord.id, not a shared/representative ID.
List<SiteRecord> filterRegisteredSites(
  Iterable<SiteRecord> sites, {
  String query = '',
  SiteStatus? status,
}) {
  final needle = query.trim().toLowerCase();
  return sites.where((site) {
    if (status != null && site.status != status) return false;
    final haystack = [
      site.name,
      site.customerName,
      site.address,
      site.managerName,
      site.nearestStation,
      site.formalName,
      site.representativeName,
      site.notes,
      site.id,
    ].join(' ').toLowerCase();
    return needle.isEmpty || haystack.contains(needle);
  }).toList();
}
