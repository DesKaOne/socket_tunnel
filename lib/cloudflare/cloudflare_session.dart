import 'package:socket_client/socket_client.dart';

import '../puppeteer/puppeteer.dart';

class CloudflareSession {
  final String cookieHeader;
  final String userAgent;
  final String html;

  CloudflareSession({
    required this.cookieHeader,
    required this.userAgent,
    required this.html,
  });

  Map<String, dynamic> toJson() {
    return {'cookie': cookieHeader, 'user-agent': userAgent};
  }

  @override
  String toString() => 'Session(cookie=$cookieHeader, user-agent=$userAgent)';

  static Future<CloudflareSession> create(
    HttpClientCore client,
    String url,
    String userAgent, {
    List<CookieParam> addCookies = const [],
  }) async {
    final browser = await puppeteer.launch(
      headless: true,
      args: [
        // tambah argumen aman di server
        '--no-sandbox', '--disable-setuid-sandbox',
      ],
      client: client,
    );
    try {
      final page = await browser.newPage();
      // penting: UA yang akan kamu pakai terus-menerus
      await page.setUserAgent(userAgent);
      if (addCookies.isNotEmpty) {
        await page.setCookies(addCookies);
      }

      // buka halaman form dan tunggu network idle (biar CF selesai)
      await page.goto(url, wait: Until.networkIdle);

      // ekstra “aman”, tunggu 1–2 detik acak
      await Future.delayed(Duration(milliseconds: 800));

      final cookies = await page.cookies();
      // Rakit cookie header (harus ada cf_clearance/ __cf_bm kalau CF aktif)
      final cookieHeader = cookies
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      final html = await page.content;
      return CloudflareSession(
        cookieHeader: cookieHeader,
        userAgent: userAgent,
        html: html!,
      );
    } catch (error) {
      rethrow;
    } finally {
      //await browser.close();
    }
  }
}
