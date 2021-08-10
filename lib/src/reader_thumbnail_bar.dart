import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import './reader_controller.dart';
import './reader_image.dart';

typedef ReaderThumbnailBarFrameBuilder = Widget Function(BuildContext context,
    Widget child, ReaderPageInfo pageInfo, bool focus, bool active);

class ReaderThumbnailBar extends StatefulWidget {
  final ReaderController controller;
  final ImageProviderBuilder imageBuilder;
  final BoxDecoration? backgroundDecoration;
  final ReaderImageLoadingBuilder? loadingBuilder;
  final ReaderImageErrorBuilder? errorBuilder;
  final ReaderThumbnailBarFrameBuilder? frameBuilder;
  final Duration activeAnimationDuration;
  final Curve activeAnimationCurve;

  int get itemCount => controller.itemCount;

  final double thumbnailWidth;

  final double barHeight;

  final double space;
  final double focusScale;
  final double activeWidth;
  final double activeHeight;
  final EdgeInsets activeMargin;

  final bool immediate;
  final EdgeInsets padding;

  const ReaderThumbnailBar({
    Key? key,
    required this.controller,
    required this.imageBuilder,
    this.loadingBuilder,
    this.errorBuilder,
    this.frameBuilder,
    this.thumbnailWidth = 15,
    this.barHeight = 50,
    this.focusScale = 1.8,
    this.activeWidth = 150,
    this.activeHeight = 500,
    this.activeMargin = const EdgeInsets.only(bottom: 90),
    this.space = 1,
    this.activeAnimationDuration = const Duration(milliseconds: 60),
    this.activeAnimationCurve = Curves.easeOut,
    this.immediate = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 8.0),
    this.backgroundDecoration = const BoxDecoration(color: Color(0xAA000000)),
  }) : super(key: key);

  @override
  State<ReaderThumbnailBar> createState() => _ReaderThumbnailBarState();
}

class _ReaderThumbnailBarState extends State<ReaderThumbnailBar>
    with SingleTickerProviderStateMixin {
  late StreamSubscription stateSubscription;
  late final AnimationController activeAnimationController;
  late final Animation<Size> activeSize;
  late final Animation<EdgeInsets> activeMargin;

  @override
  void initState() {
    super.initState();
    activeAnimationController = AnimationController(
        duration: widget.activeAnimationDuration, vsync: this);
    final CurvedAnimation curve = CurvedAnimation(
        parent: activeAnimationController, curve: widget.activeAnimationCurve);
    activeSize = Tween(
            begin: Size(widget.thumbnailWidth * widget.focusScale, widget.barHeight),
            end: Size(widget.activeWidth, widget.activeHeight))
        .animate(curve);
    activeMargin =
        Tween(begin: const EdgeInsets.all(0), end: widget.activeMargin)
            .animate(curve);
    stateSubscription = widget.controller.stateChange.listen((event) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    activeAnimationController.dispose();
    stateSubscription.cancel();
    super.dispose();
  }

  bool get active => panOffset != null;

  jump(Offset offset, double width, double padding) {
    final index = getIndex(offset, width, padding);
    widget.controller.jumpToIndex(index);
  }

  int getIndex(Offset offset, double width, double padding) {
    var index =
        ((offset.dx - padding) / (width - padding) * widget.itemCount).round();
    if (index < 0) index = 0;
    if (index >= widget.itemCount) index = widget.itemCount - 1;
    if (widget.controller.reverse) {
      return (widget.itemCount - 1) - index;
    }
    return index;
  }

  Offset? panOffset;

  int? pageChangeMark;

  Widget image(ReaderPageInfo pageInfo,
      [bool focus = false, bool active = false]) {
    final image = ReaderImage(
      controller: widget.controller,
      pageInfo: pageInfo,
      imageBuilder: widget.imageBuilder,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
      // frameBuilder: widget.frameBuilder,
      cushionPrefix: 'thumbnail',
    );
    return image;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          minHeight:
              widget.barHeight + widget.padding.top + widget.padding.top),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final boxWidth =
              constraints.maxWidth - widget.padding.left - widget.padding.right;
          final maxCount =
              (boxWidth / (widget.thumbnailWidth + widget.space)).truncate();
          final count = max(min(maxCount, widget.itemCount), 0);
          final width = (boxWidth / maxCount - widget.space);
          var imageList = List.generate(count, (index) {
            final realIndex = ((index / count) * widget.itemCount).round();
            final pageInfo = widget.controller.getPagesFromIndex(realIndex);
            var child = image(pageInfo);
            if (widget.frameBuilder != null) {
              child =
                  widget.frameBuilder!(context, child, pageInfo, false, false);
            }
            return ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: widget.barHeight, maxWidth: width),
              child: child,
            );
          });
          if (widget.controller.reverse) {
            imageList = imageList.reversed.toList();
          }
          return GestureDetector(
            onPanUpdate: (DragUpdateDetails details) {
              setState(() {
                panOffset = details.localPosition;
              });
              if (active && widget.immediate) {
                jump(details.localPosition, boxWidth, width);
              }
            },
            onPanStart: (details) {
              activeAnimationController.forward();
              setState(() {
                panOffset = details.localPosition;
              });
              if (widget.immediate) {
                jump(details.localPosition, boxWidth, width);
              }
            },
            onPanCancel: () {
              activeAnimationController.reverse();
              setState(() {
                panOffset = null;
              });
            },
            onPanEnd: (details) {
              activeAnimationController.reverse();
              if ((!widget.immediate) && panOffset != null) {
                jump(panOffset!, boxWidth, width);
              }
              setState(() {
                panOffset = null;
              });
            },
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: widget.backgroundDecoration,
                        height: widget.barHeight,
                        padding: widget.padding,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: imageList,
                        ),
                      ),
                    ),
                  ),
                ),
                StreamBuilder<int>(
                    stream: widget.controller.currentPageStream,
                    initialData: widget.controller.currentPage,
                    builder: (context, snapshot) {
                      var index =
                          widget.controller.pageToIndex(snapshot.data ?? 0);
                      if (active) {
                        index = getIndex(panOffset!, boxWidth, width);
                        if (index != pageChangeMark) {
                          pageChangeMark = index;
                          HapticFeedback.selectionClick();
                        }
                      }
                      var x = (index / (widget.itemCount - 1)) * 2 - 1;
                      x *= boxWidth / constraints.maxWidth; // add padding
                      if (widget.controller.reverse) {
                        x = 0 - x;
                      }
                      final pageInfo =
                          widget.controller.getPagesFromIndex(index);
                      return Align(
                        alignment: Alignment(x, 1),
                        child: AnimatedBuilder(
                            animation: activeAnimationController,
                            child: image(pageInfo),
                            builder: (BuildContext context, Widget? child) {
                              final active = activeAnimationController.status !=
                                  AnimationStatus.dismissed;
                              if (widget.frameBuilder != null &&
                                  child != null) {
                                child = widget.frameBuilder!(
                                    context, child, pageInfo, true, active);
                              }
                              return Container(
                                width: activeSize.value.width,
                                height: activeSize.value.height,
                                padding: activeMargin.value,
                                alignment: active
                                    ? Alignment.bottomCenter
                                    : Alignment.center,
                                child: child,
                              );
                            }),
                      );
                    }),
              ],
            ),
          );
        },
      ),
    );
  }
}
