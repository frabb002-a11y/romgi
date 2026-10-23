import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/metadata/moby_page.dart';

/// Keeps one WebView for MobyGames. The first request often stops on
/// Cloudflare's own check; this page runs that check, then later pages
/// reuse the same view.
class MobyBrowserHost extends StatefulWidget {
  const MobyBrowserHost({super.key});

  @override
  State<MobyBrowserHost> createState() => _MobyBrowserHostState();
}

class _MobyBrowserHostState extends State<MobyBrowserHost> {
  late final WebViewController _controller;
  Future<void> _queue = Future<void>.value();
  var _visible = false;
  var _pageFinished = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _pageFinished++;
          },
        ),
      );
    MobyBrowser.load = _load;
  }

  @override
  void dispose() {
    if (MobyBrowser.load == _load) MobyBrowser.load = null;
    super.dispose();
  }

  Future<String> _load(String url, {CancelToken? cancelToken}) {
    final result = _queue.then((_) => _loadNow(url, cancelToken));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _loadNow(String url, CancelToken? cancelToken) async {
    if (!mounted) {
      throw const MobyPageException(
        'MobyGames asked for a browser check. Open Romgi and start the build again.',
      );
    }
    setState(() => _visible = true);
    await WidgetsBinding.instance.endOfFrame;
    final started = _pageFinished;
    await _controller.loadRequest(Uri.parse(url));

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (cancelToken?.isCancelled ?? false) {
        if (mounted) setState(() => _visible = false);
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: 'cancelled',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_pageFinished <= started) continue;
      final current = await _controller.currentUrl();
      if (!_sameListingUrl(current, url)) continue;
      late final String html;
      try {
        html = await _readHtml();
      } catch (_) {
        continue;
      }
      if (html.length < 500) continue;
      if (!mobyPageLooksBlocked(html)) {
        if (mounted) setState(() => _visible = false);
        return html;
      }
    }
    if (mounted) setState(() => _visible = false);
    throw const MobyPageException(
      'MobyGames asked for a browser check and it did not finish. '
      'Leave the check on screen until the list appears, then try again.',
    );
  }

  bool _sameListingUrl(String? current, String requested) {
    if (current == null || current.isEmpty) return false;
    String trim(String value) {
      final bare = value.split('#').first.split('?').first;
      return bare.endsWith('/') ? bare.substring(0, bare.length - 1) : bare;
    }

    return trim(current).toLowerCase() == trim(requested).toLowerCase();
  }

  Future<String> _readHtml() async {
    final value = await _controller.runJavaScriptReturningResult(
      'document.documentElement.outerHTML',
    );
    final text = value.toString();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) return decoded;
      } catch (_) {}
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Offstage(
        offstage: !_visible,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text(
                    'MobyGames is checking this browser. If a box appears, complete it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(child: WebViewWidget(controller: _controller)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
