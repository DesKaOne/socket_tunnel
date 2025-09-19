abstract class BaseApiIpInfo {
  final bool status;
  final String host;
  final String asn;
  final String asName;
  final String country;

  BaseApiIpInfo({
    required this.status,
    required this.host,
    required this.asn,
    required this.asName,
    required this.country,
  });
}
