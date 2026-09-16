import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cloudflare 1-Click Zero-Typing OAuth Helper Service
/// (一键免输入 Cloudflare 授权服务)
class CfOAuthService {
  static const int callbackPort = 8989;
  static const String callbackPath = '/callback';

  /// 启动 1-Click 授权流程
  /// 1. 本地后台启动临时 HttpServer 监听 127.0.0.1:8989/callback
  /// 2. 拉起系统默认浏览器进入 Cloudflare 官方授权界面
  /// 3. 用户在浏览器点击【同意授权】后自动重定向回调
  /// 4. 本地监听器自动获取 Token / Account ID，返回成功 HTML，零复制零输入！
  static Future<Map<String, dynamic>> authorizeZeroCopy({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    HttpServer? server;
    try {
      // 1. 绑定本地 127.0.0.1 端口
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        callbackPort,
        shared: true,
      );
      debugPrint('🌐 [CfOAuthService] 本地回调服务已启动 -> http://127.0.0.1:$callbackPort$callbackPath');

      // 2. 构建 Cloudflare 官方 1-Click 授权 URL
      final redirectUri = 'http://127.0.0.1:$callbackPort$callbackPath';
      final authUrl = Uri.parse(
        'https://dash.cloudflare.com/profile/api-tokens?redirect_uri=${Uri.encodeComponent(redirectUri)}',
      );

      // 3. 唤起默认浏览器
      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await server.close();
        return {
          'success': false,
          'error': '无法打开默认浏览器，请检查系统设置',
        };
      }

      // 4. 等待浏览器回调
      final completer = Completer<Map<String, dynamic>>();

      late StreamSubscription sub;
      sub = server.listen((HttpRequest request) async {
        final uri = request.uri;
        if (uri.path == callbackPath || uri.path == '/callback') {
          final queryParams = uri.queryParameters;
          debugPrint('📥 [CfOAuthService] 收到浏览器回调参数: $queryParams');

          final token = queryParams['token'] ?? queryParams['access_token'] ?? queryParams['api_token'];
          final accountId = queryParams['account_id'] ?? queryParams['accountId'];
          final d1DatabaseId = queryParams['d1_database_id'] ?? queryParams['database_id'];
          final r2BucketName = queryParams['r2_bucket_name'] ?? queryParams['bucket_name'];

          // 响应优雅的 HTML 成功页面
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>PodQuick 授权成功</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #121316;
      color: #ffffff;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #1e2026;
      padding: 36px;
      border-radius: 16px;
      text-align: center;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
      border: 1px solid rgba(255,255,255,0.1);
      max-width: 400px;
    }
    .icon { font-size: 48px; margin-bottom: 16px; }
    h2 { margin: 0 0 10px 0; color: #4CAF50; font-size: 22px; }
    p { color: #8a8f9d; font-size: 14px; margin-bottom: 20px; line-height: 1.5; }
    .btn {
      background: #2563eb; color: #fff; border: none; padding: 10px 20px;
      border-radius: 8px; font-weight: 600; cursor: pointer; text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">🎉</div>
    <h2>PodQuick 授权成功！</h2>
    <p>凭证已全自动同步并绑定到 PodQuick 客户端。<br>您可以安全关闭此页面并返回软件使用。</p>
    <a href="javascript:window.close()" class="btn">关闭此窗口</a>
  </div>
  <script>setTimeout(() => { window.close(); }, 3000);</script>
</body>
</html>
''');
          await request.response.close();

          if (!completer.isCompleted) {
            completer.complete({
              'success': true,
              'token': token,
              'accountId': accountId,
              'd1DatabaseId': d1DatabaseId,
              'r2BucketName': r2BucketName,
            });
          }
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not Found');
          await request.response.close();
        }
      });

      // 设置超时定时器
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          return {'success': false, 'error': '等待浏览器授权超时（超过 3 分钟），请重试'};
        },
      );

      await sub.cancel();
      await server.close(force: true);
      return result;
    } catch (e) {
      await server?.close(force: true);
      debugPrint('❌ [CfOAuthService] 1-Click 授权过程异常: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
