import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'image_size.dart';

typedef ReaderImageLoader = Future<Stream<List<int>>> Function(StreamController<ReaderImageChunkEvent>);

typedef ImageSizeCallback = void Function(Size size);

class ReaderImageChunkEvent extends ImageChunkEvent {
  final Object? stage;
  const ReaderImageChunkEvent({
    required int cumulativeBytesLoaded,
    required int? expectedTotalBytes,
    this.stage,
  }) : super(cumulativeBytesLoaded: cumulativeBytesLoaded, expectedTotalBytes: expectedTotalBytes);
}

class ReaderImageProvider extends ImageProvider<ReaderImageProvider> {
  ReaderImageProvider(this.key, this.loader, { this.scale = 1.0 });

  final String key;

  final ReaderImageLoader loader;

  final double scale;

  ImageSizeCallback? sizeCallback;

  @override
  Future<ReaderImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<ReaderImageProvider>(this);
  }
/*
  @override
  ImageStreamCompleter load(ReaderImageProvider key, DecoderCallback decode) {
    // Ownership of this controller is handed off to [_loadAsync]; it is that
    // method's responsibility to close the controller's stream when the image
    // has been loaded or an error is thrown.
    final StreamController<ImageChunkEvent> chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key as ReaderImageProvider, chunkEvents, null, decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: imageStream.key,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<ReaderImageProvider>('Image key', key),
      ],
    );
  }*/

  @override
  ImageStreamCompleter loadBuffer(ReaderImageProvider key, DecoderBufferCallback decode) {
    // Ownership of this controller is handed off to [_loadAsync]; it is that
    // method's responsibility to close the controller's stream when the image
    // has been loaded or an error is thrown.
    final StreamController<ReaderImageChunkEvent> chunkEvents = StreamController<ReaderImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key as ReaderImageProvider, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: this.key,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<ReaderImageProvider>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
      ReaderImageProvider key,
      StreamController<ReaderImageChunkEvent> chunkEvents,
      DecoderBufferCallback decode
      ) async {
    try {
      assert(key == this);
      final _OutputBuffer output = _OutputBuffer();
      ByteConversionSink sink = output;
      final bytesStream = await loader(chunkEvents);
      bytesStream.listen((chunk) {
        output.add(chunk);
      });

      int bytesReceived = 0;
      bool obtainedImageSize = false;
      await for(final chunk in bytesStream) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        if((!obtainedImageSize) && sizeCallback != null) {
          if(bytesReceived > 32) {
            final size = ImageSize.getSize(output.getBytes());
            if(size != null) {
              obtainedImageSize = true;
              final imageSize = Size(size.width.toDouble(), size.height.toDouble());
              if(sizeCallback != null) sizeCallback!(imageSize);
            }
            if(bytesReceived > 512 && size == null) {
              obtainedImageSize = true;
            }
          }
        }
      }
      sink.close();
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(output.getBytes());
      return decode(buffer);
    } catch (e) {
      // Depending on where the exception was thrown, the image cache may not
      // have had a chance to track the key in the cache at all.
      // Schedule a microtask to give the cache a chance to add the key.
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is ReaderImageProvider
        && other.key == key
        && other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(key, scale);

  @override
  String toString() => '${objectRuntimeType(this, 'ReaderImageProvider')}("$key", scale: $scale)';
}

class _OutputBuffer extends ByteConversionSinkBase {
  List<List<int>>? _chunks = <List<int>>[];
  int _contentLength = 0;
  Uint8List? _bytes;

  @override
  void add(List<int> chunk) {
    assert(_bytes == null);
    _chunks!.add(chunk);
    _contentLength += chunk.length;
  }

  @override
  void close() {
    if (_bytes != null) {
      // We've already been closed; this is a no-op
      return;
    }
    _bytes = Uint8List(_contentLength);
    int offset = 0;
    for (final List<int> chunk in _chunks!) {
      _bytes!.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _chunks = null;
  }

  Uint8List getBytes() {
    final bytes = Uint8List(_contentLength);
    int offset = 0;
    for (final List<int> chunk in _chunks!) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return bytes;
  }


  Uint8List get bytes {
    assert(_bytes != null);
    return _bytes!;
  }
}

