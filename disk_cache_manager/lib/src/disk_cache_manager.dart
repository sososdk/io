import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:disk_cache/disk_cache.dart';
import 'package:file_system/file_system.dart';
import 'package:pool/pool.dart';

const int _kVersion = 202204;
const int _kEntryMetadata = 0;
const int _kEntryBody = 1;
const int _kEntryCount = 2;

/// This manager handles the work with file cache.
class DiskCacheManager {
  DiskCacheManager(
    FileSystem fileSystem,
    String directory, {
    int? maxSize,
    int maxConcurrent = 10,
    Fetcher? fetcher,
  })  : _cache = DiskCache(fileSystem, directory,
            appVersion: _kVersion, valueCount: _kEntryCount, maxSize: maxSize),
        _pool = Pool(maxConcurrent),
        _fetcher = fetcher ?? _DefaultFetcher();

  final DiskCache _cache;
  final Pool _pool;
  final Fetcher _fetcher;
  final _fetching = <String, _FetchingCompleter>{};
  bool _closed = false;

  Future<T> get<T>(
    String url, {
    Options options = const Options(),
    ProgressCallback? downloadProgress,
    required Transformer<CacheResponse, T> transformer,
  }) {
    var fetching = _fetching[url] as _FetchingCompleter<T>?;
    if (fetching == null) {
      _fetching[url] = fetching = _FetchingCompleter<T>();
      fetch(url, options: options)
          .then((e) {
            final body = e.body;
            final totalLength = e.length;
            if (totalLength > 0 && body is _ReceivedSource) {
              body.listener = (received) {
                for (final downloadProgress in _fetching[url]!.listeners) {
                  downloadProgress(received / totalLength);
                }
              };
            }
            return transformer.transform(e);
          })
          .then((e) => fetching!.complete(e))
          .catchError((e, s) => fetching!.completeError(e, s))
          .whenComplete(() => _fetching.remove(url));
    }
    if (downloadProgress != null) {
      fetching.addListener(downloadProgress);
    }
    return fetching.future;
  }

  Future<CacheResponse> fetch(
    String url, {
    Options options = const Options(),
  }) async {
    _checkClose();
    final key = _genKey(url);
    final snapshot = await _cache.get(key).catchError((e) {
      // Give up because the cache cannot be read.
    });
    if (snapshot != null) {
      try {
        return CacheResponse.fromCache(snapshot);
      } catch (e) {
        await snapshot.close().catchError((_) {});
      }
    }
    var resource = await _pool.request();
    try {
      final response = await _fetcher.fetch(url, options: options);
      final editor = await _cache.edit(key);
      if (editor == null) {
        return response;
      } else {
        return CacheResponse.fromResponse(response, editor);
      }
    } finally {
      resource.release();
    }
  }

  void _checkClose() {
    if (_closed) {
      throw StateError('fetch() may not be called on a closed manager.');
    }
  }

  Future<bool> remove(String url) {
    _checkClose();
    return _cache.remove(_genKey(url));
  }

  Future<void> clear() {
    _checkClose();
    return _cache.evictAll();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _fetcher.close();
    await _cache.close();
    await _pool.close();
  }

  String _genKey(String url) => md5.convert(url.codeUnits).toString();
}

/// A cache response.
class CacheResponse {
  CacheResponse(
    this.url,
    this.method,
    this.headers,
    this.code,
    this.length,
    this.body,
  );

  /// The final real request url (maybe redirect).
  final String url;

  /// Http method.
  final String method;

  /// Response headers.
  final Map<String, List<String>> headers;

  /// Returns the HTTP status code.
  final int code;

  /// Response length. Returns -1 if the size of the response body is not known in advance.
  final int length;

  /// Response body.
  final Source body;

  static Future<CacheResponse> fromCache(Snapshot snapshot) async {
    final metadataSource = snapshot.getSource(_kEntryMetadata).buffer();
    final url = await metadataSource.readLineStrict();
    final method = await metadataSource.readLineStrict();
    final headers = (jsonDecode(await metadataSource.readLineStrict()) as Map)
        .map((key, value) => MapEntry(key as String, List<String>.from(value)));
    final code = int.parse(await metadataSource.readLineStrict());
    final body = _CacheSourceBody(snapshot);
    return CacheResponse(
        url, method, headers, code, snapshot.getLength(_kEntryBody), body);
  }

  static Future<CacheResponse> fromResponse(
      CacheResponse response, Editor editor) async {
    final url = response.url;
    final method = response.method;
    final headers = response.headers;
    final code = response.code;
    final metadataSink = await editor.newSink(_kEntryMetadata).buffer();
    await metadataSink.writeLine(url);
    await metadataSink.writeLine(method);
    await metadataSink.writeLine(jsonEncode(headers));
    await metadataSink.writeLine('${response.code}');
    await metadataSink.close();
    final bodySink = await editor.newSink(_kEntryBody);
    final body = _CacheSinkBody(editor, response.body, bodySink);
    return CacheResponse(
        url, method, headers, code, response.length, _ReceivedSource(body));
  }
}

/// Defines a fetcher.
abstract class Fetcher {
  Future<CacheResponse> fetch(String url, {Options options});

  Future<void> close();
}

/// An options for fetcher.
class Options {
  final String method;
  final Map<String, List<String>>? headers;
  final Object? body;
  final Duration connectTimeout;
  final Duration writeTimeout;
  final Duration readTimeout;
  final bool followRedirects;
  final int maxRedirects;
  final int retries;
  final bool persistentConnection;
  final Map<String, dynamic>? extra;

  const Options({
    this.method = 'GET',
    this.headers,
    this.body,
    this.connectTimeout = const Duration(seconds: 10),
    this.writeTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 10),
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.retries = 3,
    this.persistentConnection = true,
    this.extra,
  });
}

abstract class Transformer<S, T> {
  FutureOr<T> transform(S value);
}

typedef ProgressCallback = void Function(double percent);

class _CacheSourceBody extends ForwardingSource {
  _CacheSourceBody(this.snapshot) : super(snapshot.getSource(_kEntryBody));

  final Snapshot snapshot;

  @override
  Future<void> close() async {
    await snapshot.close();
  }
}

class _CacheSinkBody extends Source {
  _CacheSinkBody(this.editor, this.bodySource, Sink bodySink)
      : bodySink = bodySink.buffer();

  final Editor editor;
  final Source bodySource;
  final BufferedSink bodySink;
  var _cacheRequestClosed = false;
  var _done = false;

  @override
  Future<int> read(Buffer sink, int count) async {
    int bytesRead = 0;
    try {
      bytesRead = await bodySource.read(sink, count);
    } catch (e) {
      if (!_done) {
        _done = true;
        // Failed to write a complete cache response.
        await bodySink.close();
        await editor.abort();
      }
      rethrow;
    }
    if (bytesRead == 0) {
      if (!_done) {
        _done = true;
        await bodySink.close(); // The cache response is complete!
        await editor.commit();
      }
      return 0;
    }
    sink.copyTo(bodySink.buffer, sink.length - bytesRead, sink.length);
    await bodySink.emit();
    return bytesRead;
  }

  @override
  Future<void> close() async {
    if (!_cacheRequestClosed) {
      _cacheRequestClosed = true;
      if (!await discard()) {
        if (!_done) {
          _done = true;
          await bodySink.close();
          await editor.abort();
        }
      }
      await bodySource.close();
    }
  }
}

class _DefaultFetcher implements Fetcher {
  _DefaultFetcher([HttpClient? client]) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<CacheResponse> fetch(
    String url, {
    Options options = const Options(),
  }) async {
    assert(options.method == 'GET');
    final method = options.method;
    var requestFuture = _client.openUrl(method, Uri.parse(url));
    final connectTimeout = options.connectTimeout;
    if (connectTimeout != Duration.zero) {
      requestFuture = requestFuture.timeout(connectTimeout);
    }
    final request = (await requestFuture)
      ..followRedirects = options.followRedirects
      ..maxRedirects = options.maxRedirects
      ..persistentConnection = options.persistentConnection;
    options.headers?.forEach((key, value) {
      request.headers.add(key, value);
    });
    // Transform the request data.
    // Stream<List<int>>? dataStream;
    // if (dataStream != null) {
    //   // Set content length.
    //   request.contentLength = -1;
    //   final writeTimeout = options.writeTimeout;
    //   if (writeTimeout != Duration.zero) {
    //     dataStream = dataStream.timeout(writeTimeout);
    //   }
    //   await request.addStream(dataStream);
    // }
    // Close the request and return the response.
    var responseFuture = request.close();
    final writeTimeout = options.writeTimeout;
    if (writeTimeout != Duration.zero) {
      responseFuture = responseFuture.timeout(writeTimeout);
    }
    final response = await responseFuture;
    final code = response.statusCode;
    if (code > 299 || code < 200) {
      throw HttpException(
        'Invalid statusCode: ${response.statusCode}',
        uri: request.uri,
      );
    }
    final responseHeaders = <String, List<String>>{};
    response.headers.forEach((key, values) {
      responseHeaders[key] = values;
    });
    Stream<List<int>> stream = response;
    final readTimeout = options.readTimeout;
    if (readTimeout != Duration.zero) {
      stream = response.timeout(readTimeout);
    }

    return CacheResponse(
      response.isRedirect ? response.redirects.last.location.toString() : url,
      method,
      responseHeaders,
      response.statusCode,
      response.contentLength,
      StreamSource(stream),
    );
  }

  @override
  Future<void> close() async {
    _client.close(force: true);
  }
}

class _ReceivedSource extends ForwardingSource {
  _ReceivedSource(Source delegate) : super(delegate);

  void Function(int reveived)? listener;
  int _received = 0;

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    final read = await super.read(sink, count);
    if (read != 0) listener?.call(_received += read);
    return read;
  }
}

class _FetchingCompleter<T> implements Completer<T> {
  final _completer = Completer<T>();
  final List<ProgressCallback> _listeners = [];

  void addListener(ProgressCallback listener) {
    _listeners.add(listener);
  }

  List<ProgressCallback> get listeners => _listeners;

  @override
  void completeError(Object error, [StackTrace? stackTrace]) {
    _completer.completeError(error, stackTrace);
  }

  @override
  void complete([FutureOr<T>? value]) {
    _completer.complete(value);
  }

  @override
  Future<T> get future => _completer.future;

  @override
  bool get isCompleted => _completer.isCompleted;
}
