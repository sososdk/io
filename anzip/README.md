<!-- 
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/guides/libraries/writing-package-pages). 

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-library-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/developing-packages). 
-->

A dart library for zip files / streams.

## Features

Currently only the decompression function is supported.

* Support for both AES and zip standard encryption methods
* Support for Zip64 format
* Store (No Compression) and Deflate compression method
* Extract files from split zip files (Ex: z01, z02,...zip)

## Usage

```dart
// Open a zip file and paras header.
final zipFile = await ZipFile.file(File('path'));

// Gat all file headers.
final headers = zipFile.fileHeaders;

// Get a zip entry source.
final entrySource = await zipFile.getEntrySource(headers.first);

// Zip entry source can be read into memory or saved to a file.
...

// Close resource
await entrySource?.close();
```

Or use `use` and `file_system`:
```dart
final fileSystem = LocalFileSystem();
final zipFile = await ZipFile.file(fileSystem.file(path));
await zipFile.openRead().use((handle) async {
    for (final header in zipFile.fileHeaders) {
        await zipFile.getZipEntrySource(handle, header).use((source) =>
            fileSystem
                .openSink(join(output, header.fileName), recursive: true)
                .buffered()
                .use((sink) => sink.writeFromSource(source)));
    }
});
```

## References

- https://en.wikipedia.org/wiki/ZIP_(file_format)
