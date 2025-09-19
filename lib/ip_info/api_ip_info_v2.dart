import 'dart:convert';
import 'dart:math';

import 'package:http_client/http_client.dart';

import 'base_api_ip_info.dart';

class ApiIpInfoV2 extends BaseApiIpInfo {
  ApiIpInfoV2({
    required super.host,
    required super.status,
    required super.asn,
    required super.asName,
    required super.country,
  });

  Map<String, dynamic> toJson() {
    return {'status': status, 'asn': asn, 'asName': asName, 'country': country};
  }

  static final Random _random = Random();

  static const String _ipInfoToken = '609d2df55501bd';

  static HttpClientCore _createConnection(List<ProxyConfig> proxies) {
    List<ProxyConfig> proxies0 = [];
    if (_random.nextBool()) proxies0 = proxies;
    return HttpClientCore.build(proxies: proxies0);
  }

  static Future<ApiIpInfoV2> getCountry({
    required List<ProxyConfig> proxies,
    required String ip,
    String? token,
  }) async {
    List<String> urls = [
      'https://api.ipinfo.io/lite/$ip?token=${token ?? _ipInfoToken}',
      'https://ipinfo.io/$ip/json',
    ];
    final String apiUrl = urls[_random.nextInt(urls.length)];

    try {
      final response = await _createConnection(proxies).get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return ApiIpInfoV2(
          status: true,
          host: data['ip'],
          asn: data['asn'] ?? 'unknown',
          asName: data['as_name'] ?? 'unknown',
          country: data['country_code'] ?? 'unknown',
        );
      } else {
        return ApiIpInfoV2(
          status: false,
          host: response.body,
          asn: 'unknown',
          asName: 'unknown',
          country: 'unknown',
        );
      }
    } catch (e) {
      return ApiIpInfoV2(
        status: false,
        host: e.toString(),
        asn: 'unknown',
        asName: 'unknown',
        country: 'unknown',
      );
    }
  }

  static Future<ApiIpInfoV2> getIpInfo({
    required List<ProxyConfig> proxies,
    String? token,
  }) async {
    List<String> urls = [
      'https://api.ipinfo.io/lite/me?token=${token ?? _ipInfoToken}',
      'https://ipinfo.io/json',
    ];
    final String apiUrl = urls[_random.nextInt(urls.length)];

    try {
      final response = await _createConnection(proxies).get(Uri.parse(apiUrl));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return ApiIpInfoV2(
          status: true,
          host: data['ip'],
          asn: data['asn'] ?? 'unknown',
          asName: data['as_name'] ?? 'unknown',
          country: data['country_code'] ?? 'unknown',
        );
      } else {
        return ApiIpInfoV2(
          status: false,
          host: response.body,
          asn: 'unknown',
          asName: 'unknown',
          country: 'unknown',
        );
      }
    } catch (e) {
      return ApiIpInfoV2(
        status: false,
        host: e.toString(),
        asn: 'unknown',
        asName: 'unknown',
        country: 'unknown',
      );
    }
  }
}
