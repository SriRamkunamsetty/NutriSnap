import 'package:nutrisnap_app/core/services/health_connect_service.dart';

/// Scriptable stand-in for the Health Connect platform.
class FakeHealth implements HealthDataSource {
  HcAvailability avail = HcAvailability.available;
  bool grant = true; // will the user grant when asked
  bool granted = false; // currently granted
  bool throwOnRead = false;
  bool installOpened = false;
  bool revoked = false;
  int reads = 0;
  List<RawHealthRecord> records = [];
  final permissionRequests = <Set<HcGroup>>[];

  @override
  Future<HcAvailability> availability() async => avail;

  @override
  Future<bool> hasPermissions(Set<HcGroup> groups) async => granted;

  @override
  Future<bool> requestPermissions(Set<HcGroup> groups) async {
    permissionRequests.add(groups);
    granted = grant;
    return grant;
  }

  @override
  Future<List<RawHealthRecord>> read(Set<HcGroup> groups, DateTime from, DateTime to) async {
    reads++;
    if (throwOnRead) throw Exception('boom');
    return records;
  }

  @override
  Future<void> revoke() async {
    revoked = true;
    granted = false;
  }

  @override
  Future<void> openInstall() async => installOpened = true;
}
