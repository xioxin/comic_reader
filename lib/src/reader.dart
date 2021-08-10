import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import './reader_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'reader_controller.dart';

typedef ReaderFrameBuilder = Widget Function(
    BuildContext context, Widget child, ReaderPageInfo pageInfo);
typedef ReaderSeparatorBuilder = Widget Function(
    BuildContext context, ReaderPageInfo pageInfo);

class Reader extends StatefulWidget {
  final ReaderController controller;
  final ImageProviderBuilder imageBuilder;
  final ReaderImageLoadingBuilder? loadingBuilder;
  final ReaderImageErrorBuilder? errorBuilder;
  final BoxDecoration? backgroundDecoration;
  final ReaderFrameBuilder? frameBuilder;
  final ReaderSeparatorBuilder? separatorBuilder;
  final EdgeInsets padding;

  Reader({
    Key? key,
    required this.imageBuilder,
    required this.controller,
    this.loadingBuilder,
    this.errorBuilder,
    this.backgroundDecoration,
    this.frameBuilder,
    this.separatorBuilder,
    this.padding = const EdgeInsets.all(0),
  }) : super(key: key) {
    // controller.imageSizeChange.listen((event) {
    //   print(event);
    // });
  }

  @override
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  late StreamSubscription stateSubscription;

  @override
  void initState() {
    super.initState();
    stateSubscription = widget.controller.stateChange.listen((event) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    stateSubscription.cancel();
  }

  Widget image(ReaderPageInfo pageInfo) {
    final image = ReaderImage(
      controller: widget.controller,
      pageInfo: pageInfo,
      imageBuilder: widget.imageBuilder,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
      cushionPrefix: 'image',
    );
    if (widget.frameBuilder != null) {
      widget.frameBuilder!(context, image, pageInfo);
    }
    return image;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, BoxConstraints constraints) {
      final itemCount = widget.controller.itemCount;
      if (widget.controller.continuous) {
        final scrollDirection =
            widget.controller.scrollDirection ?? Axis.vertical;
        final reverse = (scrollDirection == Axis.vertical)
            ? false
            : widget.controller.reverse;
        return Container(
          decoration: widget.backgroundDecoration,
          child: ScrollablePositionedList.separated(
            padding: widget.padding,
            itemCount: itemCount,
            scrollDirection: widget.controller.scrollDirection ?? Axis.vertical,
            separatorBuilder: (context, index) {
              if (widget.separatorBuilder == null) return Container();
              final pageInfo = widget.controller.getPagesFromIndex(index);
              return widget.separatorBuilder!(context, pageInfo);
            },
            initialScrollIndex:
                widget.controller.pageToIndex(widget.controller.currentPage),
            reverse: reverse,
            itemBuilder: (context, index) {
              var pageInfo = widget.controller.getPagesFromIndex(index);
              return image(pageInfo);
            },
            itemScrollController: widget.controller.getItemScrollController(),
            itemPositionsListener: widget.controller.getItemPositionsListener(),
          ),
        );
      }

      return PhotoViewGallery.builder(
          backgroundDecoration: widget.backgroundDecoration,
          itemCount: itemCount,
          pageController: widget.controller.getPageController(),
          reverse: widget.controller.reverse,
          scrollDirection:
              widget.controller.horizontal ? Axis.horizontal : Axis.vertical,
          customSize: Size(constraints.maxWidth - widget.padding.horizontal,
              constraints.maxHeight - widget.padding.vertical),
          builder: (context, index) {
            var pageInfo = widget.controller.getPagesFromIndex(index);
            return PhotoViewGalleryPageOptions.customChild(
                initialScale: 1.0,
                minScale: 1.0,
                maxScale: 3.0,
                child: Center(child: image(pageInfo)));
          });
    });
  }
}
