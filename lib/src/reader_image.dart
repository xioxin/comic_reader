import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import './reader_controller.dart';

typedef ImageProviderBuilder = Future<ImageProvider> Function(
    BuildContext context, int page);

typedef ReaderImageLoadingBuilder = Widget Function(
    BuildContext context,
    int index,
    ImageChunkEvent? event,
    );

typedef ReaderImageErrorBuilder = Widget Function(
    BuildContext context,
    int index,
    Object error,
    StackTrace? stackTrace,
    );


class ReaderImage extends StatefulWidget {

  final ReaderController controller;
  final ReaderPageInfo pageInfo;
  final ImageProviderBuilder imageBuilder;
  final ReaderImageLoadingBuilder? loadingBuilder;
  final ReaderImageErrorBuilder? errorBuilder;
  final String cushionPrefix;

  const ReaderImage({
    required this.controller,
    required this.pageInfo,
    required this.imageBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.cushionPrefix = '',
    Key? key
  }) : super(key: key);

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  @override
  Widget build(BuildContext context) {
    final pageInfo = widget.pageInfo;
    var pageList = pageInfo.pageList;
    for (var page in pageList) {
      preCacheImage(page);
    }
    if(widget.controller.readDirection == TextDirection.rtl) {
      pageList = pageList.reversed.toList();
    }

    late Widget image;

    if(pageInfo.isSplit) {
      image = splitImage(pageList.first, pageInfo.subPage ?? 0);
    } else if(pageInfo.isDual) {
      image = weldImage(pageList);
    } else {
      image = singleImage(pageList.first);
    }
    return image;
  }

  Map<String, Future<ImageProvider>> get providerCache => widget.controller.providerCache;

  Future<ImageProvider> getProvider(int index) {
    final key = "${widget.cushionPrefix}-$index";
    if (providerCache.containsKey(key)) {
      return providerCache[key]!;
    }
    providerCache[key] = widget.imageBuilder(context, index);
    return providerCache[key]!;
  }

  Future<ImageInfo?> preCacheImage(int index, {
    Size? size,
    ImageErrorListener? onError,
  }) async {
    final provider = await getProvider(index);
    final ImageConfiguration config = createLocalImageConfiguration(context, size: size);
    final Completer<void> completer = Completer<void>();
    final ImageStream stream = provider.resolve(config);
    ImageStreamListener? listener;
    ImageInfo? imageImage;
    listener = ImageStreamListener(
          (ImageInfo? image, bool sync) {
        imageImage = image;
        if (image != null) {
          widget.controller.setImageSize(index, image.image.width.toDouble(),
              image.image.height.toDouble());
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
        SchedulerBinding.instance!.addPostFrameCallback((Duration timeStamp) {
          stream.removeListener(listener!);
        });
      },
      onError: (Object exception, StackTrace? stackTrace) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        stream.removeListener(listener!);
        if (onError != null) {
          onError(exception, stackTrace);
        } else {
          FlutterError.reportError(FlutterErrorDetails(
            context: ErrorDescription('image failed to precache'),
            library: 'image resource service',
            exception: exception,
            stack: stackTrace,
            silent: true,
          ));
        }
      },
    );
    stream.addListener(listener);
    await completer.future;
    return imageImage;
  }


  ImageLoadingBuilder _imageLoadingBuilder(int index) {
    return (BuildContext context, Widget child,
        ImageChunkEvent? loadingProgress) {
      if (loadingProgress == null) return child;
      return (widget.loadingBuilder ?? _defaultImageLoadingBuilder)(
          context, index, loadingProgress);
    };
  }

  Widget _defaultImageLoadingBuilder(BuildContext context,
      int index,
      ImageChunkEvent? event,) {
    if (event != null && event.expectedTotalBytes != null) {
      final p = (event.cumulativeBytesLoaded / event.expectedTotalBytes! * 100)
          .toInt();
      return Center(child: Text("$p%"));
    }
    return const Center(child: Text("Loading"));
  }

  ImageErrorWidgetBuilder _imageErrorBuilder(int index) {
    return (BuildContext context, Object error, StackTrace? stackTrace) {
      return (widget.errorBuilder ?? _defaultImageErrorBuilder)(
          context, index, error, stackTrace);
    };
  }

  Widget _defaultImageErrorBuilder(BuildContext context,
      int index,
      Object error,
      StackTrace? stackTrace,) {
    return Center(child: Text(error.toString()));
  }

  Widget splitImage(int page, int subPage) {
    final alignment = subPage == (widget.controller.isRtl ? 1 : 0) ? Alignment.centerLeft : Alignment.centerRight;
    return StreamBuilder<ReaderImageSize>(
        stream: widget.controller.getImageSizeStream(page),
        initialData: widget.controller.getImageSize(page),
        builder: (context, ratioSnapshot) {
          final size = ratioSnapshot.data!;
          return AspectRatio(
              aspectRatio: size.aspectRatio / 2,
              child: FutureBuilder<ImageProvider>(
                  future: getProvider(page),
                  builder: (BuildContext context,
                      AsyncSnapshot imageSnapshot) {
                    if (imageSnapshot.hasError) {
                      return (widget.errorBuilder ??
                          _defaultImageErrorBuilder)(context, page,
                          imageSnapshot.error!, imageSnapshot.stackTrace);
                    }
                    if (imageSnapshot.hasData) {
                      final image = imageSnapshot.data!;
                      return Image(
                        image: image,
                        fit: BoxFit.fitHeight,
                        alignment: alignment,
                        loadingBuilder: _imageLoadingBuilder(page),
                        errorBuilder: _imageErrorBuilder(page),
                      );
                    }
                    return (widget.loadingBuilder ??
                        _defaultImageLoadingBuilder)(
                        context, page, null);
                  }));
        });
  }

  Widget singleImage(int index) {
    return StreamBuilder<Size>(
        stream: widget.controller.getImageSizeStream(index),
        initialData: widget.controller.getImageSize(index),
        builder: (context, ratioSnapshot) {
          final size = ratioSnapshot.data!;
          return AspectRatio(
              aspectRatio: size.aspectRatio,
              child: FutureBuilder<ImageProvider>(
                  future: getProvider(index),
                  builder: (BuildContext context,
                      AsyncSnapshot imageSnapshot) {
                    if (imageSnapshot.hasError) {
                      return (widget.errorBuilder ??
                          _defaultImageErrorBuilder)(context, index,
                          imageSnapshot.error!, imageSnapshot.stackTrace);
                    }
                    if (imageSnapshot.hasData) {
                      final image = imageSnapshot.data!;
                      return Image(
                        image: image,
                        fit: BoxFit.fill,
                        loadingBuilder: _imageLoadingBuilder(index),
                        errorBuilder: _imageErrorBuilder(index),
                      );
                    }
                    return (widget.loadingBuilder ??
                        _defaultImageLoadingBuilder)(
                        context, index, null);
                  }));
        });
  }

  Widget weldImage(List<int> indexList) {
    return StreamBuilder<List<Size?>>(
        stream: widget.controller.getMultipleImageSizeStream(indexList),
        initialData: widget.controller.getMultipleImageSize(indexList),
        builder: (context, ratioSnapshot) {
          final sizeList = ratioSnapshot.data!;
          final ratioList = sizeList.map((e) =>
          e == null ? (widget.controller.modeRatio ?? 1.0) : e.aspectRatio).toList();
          final totalRatio = ratioList.reduce((v, e) => v + e);
          int n = 0;
          return AspectRatio(
              aspectRatio: totalRatio, child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: indexList.map((index) {
              return AspectRatio(aspectRatio: ratioList[n++], child: singleImage(index));
            }).toList(),
          ));
        });
  }
}