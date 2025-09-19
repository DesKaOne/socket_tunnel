import 'dart:convert';

import 'package:http/http.dart' as http;

import 'base_api_ip_info.dart';

class ApiIpInfo extends BaseApiIpInfo {
  ApiIpInfo({
    required super.host,
    required super.status,
    required super.asn,
    required super.asName,
    required super.country,
  });

  Map<String, dynamic> toJson() {
    return {'status': status, 'asn': asn, 'asName': asName, 'country': country};
  }

  static const String _ipInfoToken = '609d2df55501bd';

  static Future<ApiIpInfo> getCountry(String ip, {String? token}) async {
    final String apiUrl =
        'https://api.ipinfo.io/lite/$ip?token=${token ?? _ipInfoToken}';

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return ApiIpInfo(
          status: true,
          host: data['ip'],
          asn: data['asn'] ?? 'unknown',
          asName: data['as_name'] ?? 'unknown',
          country: data['country_code'] ?? 'unknown',
        );
      } else {
        return ApiIpInfo(
          status: false,
          host: 'unknown',
          asn: 'unknown',
          asName: 'unknown',
          country: 'unknown',
        );
      }
    } catch (e) {
      return ApiIpInfo(
        status: false,
        host: 'unknown',
        asn: 'unknown',
        asName: 'unknown',
        country: 'unknown',
      );
    }
  }

  static Future<ApiIpInfo> getIpInfo({String? token}) async {
    final String apiUrl =
        'https://api.ipinfo.io/lite/me?token=${token ?? _ipInfoToken}';

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return ApiIpInfo(
          status: true,
          host: data['ip'],
          asn: data['asn'] ?? 'unknown',
          asName: data['as_name'] ?? 'unknown',
          country: data['country_code'] ?? 'unknown',
        );
      } else {
        return ApiIpInfo(
          status: false,
          host: 'unknown',
          asn: 'unknown',
          asName: 'unknown',
          country: 'unknown',
        );
      }
    } catch (e) {
      return ApiIpInfo(
        status: false,
        host: 'unknown',
        asn: 'unknown',
        asName: 'unknown',
        country: 'unknown',
      );
    }
  }
}
