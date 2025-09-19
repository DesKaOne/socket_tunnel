import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_client/http_client.dart';

import 'cognito_client_exceptions.dart';

class Client {
  String? _service;
  String _userAgent = 'aws-amplify/6.6.2 auth/4 framework/1';
  String? _region;
  late String endpoint;
  late HttpClientCore _client;

  Client({
    String? endpoint,
    String? region,
    String service = 'AWSCognitoIdentityProviderService',
    HttpClientCore? client,
    String? userAgent,
  }) {
    _region = region;
    _service = service;
    _userAgent = userAgent ?? _userAgent;
    this.endpoint = endpoint ?? 'https://cognito-idp.$_region.amazonaws.com/';
    _client = client ?? HttpClientCore();
  }

  /// Makes requests on AWS API service provider
  dynamic request(
    String operation,
    Map<String, dynamic> params, {
    String? endpoint,
    String? service,
  }) async {
    final endpointReq = endpoint ?? this.endpoint;
    final targetService = service ?? _service;
    final body = json.encode(params);

    final headersReq = <String, String>{
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': '$targetService.$operation',
      'X-Amz-User-Agent': _userAgent,
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) wipter-app/1.25.849 Chrome/116.0.5845.228 Electron/26.6.10 Safari/537.36',
    };

    http.Response response;
    try {
      response = await _client.post(
        Uri.parse(endpointReq),
        headers: headersReq,
        body: body,
      );
    } catch (e) {
      if (e.toString().contains('Failed host lookup:')) {
        throw CognitoClientException('SocketException', code: 'NetworkError');
      }
      throw CognitoClientException('Unknown Error', code: 'Unknown error');
    }

    dynamic data;

    try {
      data = json.decode(utf8.decode(response.bodyBytes));
    } catch (_) {
      // expect json
    }

    if (response.statusCode < 200 || response.statusCode > 299) {
      var errorType = 'UnknownError';
      for (final header in response.headers.keys) {
        if (header.toLowerCase() == 'x-amzn-errortype') {
          errorType = response.headers[header]!.split(':')[0];
          break;
        }
      }
      if (data == null) {
        throw CognitoClientException(
          'Cognito client request error with unknown message',
          code: errorType,
          name: errorType,
          statusCode: response.statusCode,
        );
      }
      final String? dataType = data['__type'];
      final String? dataCode = data['code'];
      final code = (dataType ?? dataCode ?? errorType).split('#').removeLast();
      throw CognitoClientException(
        data['message'] ?? 'Cognito client request error with unknown message',
        code: code,
        name: code,
        statusCode: response.statusCode,
      );
    }
    return data;
  }
}
