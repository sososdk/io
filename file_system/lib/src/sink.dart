import 'dart:async';
import 'dart:convert';

import 'file_system.dart';

class FaultHidingSink extends ForwardingSink {
  final void Function() onError;
  var _hasErrors = false;

  FaultHidingSink(IOSink sink, this.onError) : super(sink);

  @override
  void add(List<int> data) {
    if (_hasErrors) {
      return;
    }
    try {
      super.add(data);
    } catch (e) {
      _hasErrors = true;
      onError();
    }
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    if (_hasErrors) {
      return;
    }
    return super.addStream(stream).catchError((_) {
      _hasErrors = true;
      onError();
    });
  }

  @override
  Future<void> flush() async {
    if (_hasErrors) {
      return;
    }
    return super.flush().catchError((_) {
      _hasErrors = true;
      onError();
    });
  }

  @override
  Future<void> close() async {
    if (_hasErrors) {
      return;
    }
    return super.close().catchError((_) {
      _hasErrors = true;
      onError();
    });
  }
}

class ForwardingSink implements IOSink {
  final IOSink delegate;

  ForwardingSink(this.delegate);

  @override
  Encoding get encoding => delegate.encoding;

  @override
  set encoding(Encoding value) => delegate.encoding = value;

  @override
  void add(List<int> data) => delegate.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      delegate.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) => delegate.addStream(stream);

  @override
  Future close() => delegate.close();

  @override
  Future get done => delegate.done;

  @override
  Future flush() => delegate.flush();

  @override
  void write(Object? object) => delegate.write(object);

  @override
  void writeAll(Iterable objects, [String separator = ""]) =>
      delegate.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => delegate.writeCharCode(charCode);

  @override
  void writeln([Object? object = ""]) => delegate.writeln(object);
}

class BlackHoleSink implements IOSink {
  BlackHoleSink({this.encoding = utf8});

  @override
  Encoding encoding;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) {
    return Future.value();
  }

  @override
  Future close() {
    return Future.value();
  }

  @override
  Future get done => Future.value();

  @override
  Future flush() => Future.value();

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable objects, [String separator = ""]) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = ""]) {}
}
