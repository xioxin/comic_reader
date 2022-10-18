import 'dart:async';
import 'dart:math';

import 'package:comic_reader/comic_reader.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lottie/lottie.dart';
import 'package:mdi/mdi.dart';
import 'book_test_data.dart';
import 'chapter.dart';

class ReaderExample extends StatefulWidget {
  final TestBookData testBookData;
  const ReaderExample({required this.testBookData, Key? key}) : super(key: key);

  @override
  State<ReaderExample> createState() => _ReaderExampleState();
}

class _ReaderExampleState extends State<ReaderExample> {
  late ReaderController controller;

  List<Chapter> chapterList = [];

  List<String> imageUrls = [];
  List<String> thumbnailUrls = [];

  bool continuous = true;

  bool firstPageAlone = true;

  bool dual = false;

  late TestBookData nowTestBook;

  setTestBook(TestBookData bookData) {
    setState(() {
      nowTestBook = bookData;
      thumbnailUrls = bookData.thumbnailUrls;
      imageUrls = bookData.imageUrls;
      chapterList = parseChapter(bookData.chapter);
      controller = ReaderController(
        pageCount: imageUrls.length,
        dual: false,
        dualLandscapeAlone: true,
        landscapeSplit: true,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    setTestBook(widget.testBookData);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Widget debugPanel() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.white.withOpacity(0.7),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            CupertinoSlidingSegmentedControl<TextDirection>(
                groupValue: controller.readDirection,
                children: const {
                  TextDirection.ltr: Icon(Mdi.formatTextdirectionLToR),
                  TextDirection.rtl: Icon(Mdi.formatTextdirectionRToL),
                },
                onValueChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    controller.readDirection = value;
                  });
                }),
            CupertinoSlidingSegmentedControl<bool>(
                groupValue: controller.continuous,
                children: const {
                  false: Text("翻页"),
                  true: Text("连续"),
                },
                onValueChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    controller.continuous = value;
                  });
                }),
            CupertinoSlidingSegmentedControl<int>(
                groupValue: {
                  null: 0,
                  Axis.horizontal: 1,
                  Axis.vertical: 2
                }[controller.scrollDirection],
                children: const {
                  0: Text("自动"),
                  1: Text("横向"),
                  2: Text("垂直"),
                },
                onValueChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    controller.scrollDirection =
                        {0: null, 1: Axis.horizontal, 2: Axis.vertical}[value];
                  });
                }),
            CupertinoSlidingSegmentedControl<int>(
                groupValue: (() {
                  if (controller.dual && controller.dualLandscapeAlone)
                    return 2;
                  if (controller.dual && !controller.dualLandscapeAlone)
                    return 1;
                  if (controller.landscapeSplit) return 3;
                  return 0;
                })(),
                children: const {
                  0: Text("普通"),
                  1: Text("合并"),
                  2: Text("仅合并窄图"),
                  3: Text("宽图拆分"),
                },
                onValueChanged: (value) {
                  print("value: $value");
                  if (value == null) return;
                  setState(() {
                    if (value == 0) {
                      controller.dual = false;
                      controller.landscapeSplit = false;
                    }
                    if (value == 1) {
                      controller.dual = true;
                      controller.dualLandscapeAlone = false;
                    }
                    if (value == 2) {
                      controller.dual = true;
                      controller.dualLandscapeAlone = true;
                    }
                    if (value == 3) {
                      controller.dual = false;
                      controller.landscapeSplit = true;
                    }
                  });
                }),
          ],
        ),
      ),
    );
  }

  Widget thumbnailFrame(BuildContext context, Widget child,
      ReaderPageInfo pageInfo, bool focus, bool active) {
    if (active) {
      final result =
          chapterList.findByPage(pageInfo.pageList.first, controller.pageCount);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (result != null) ...[
                  SizedBox(height: 8),
                  Text(
                    result.chapter.author,
                    style: Theme.of(context)
                        .textTheme
                        .caption!
                        .copyWith(fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                  if (result.chapter.title != null)
                    Opacity(
                      opacity: 0.7,
                      child: Text(
                        result.chapter.title!,
                        style: Theme.of(context)
                            .textTheme
                            .caption!
                            .copyWith(fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(height: 4),
                ],
                child
              ],
            ),
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.all(Radius.circular(5)),
            elevation: 10,
          ),
          SizedBox(height: 8),
          Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.all(Radius.circular(50)),
            elevation: 10,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "P${pageInfo.page.first}",
                    style: Theme.of(context).textTheme.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Opacity(
      opacity: focus ? 1 : 0.7,
      child: Material(
        child: child,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
        elevation: focus ? 5.0 : 2.0,
      ),
    );
  }

  Widget readerLoading(BuildContext context, int page, ImageChunkEvent? event) {
    double b = 0;
    if (event != null && event.expectedTotalBytes != null) {
      b = event.cumulativeBytesLoaded / event.expectedTotalBytes!;
    }
    
    final boxMax = max(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height);
    
    return Stack(
      children: [
        Positioned.fill(
            child: ClipRect(
              child: OverflowBox(
                maxHeight: boxMax * 2,
                maxWidth: boxMax * 2,
                child: Center(
                    child: ClipOval(
                      child: AnimatedContainer(
                          width: boxMax * b,
                          height: boxMax * b,
                          color: Colors.grey.withOpacity(0.1),
                        duration: const Duration(milliseconds: 100),
                      ),
                    ),
                ),
              ),
            )),
        Positioned.fill(
            child: Center(
                child: Lottie.asset('assets/726-ice-cream-animation.json')))
      ],
    );
  }

  Widget thumbnailLoading(
      BuildContext context, int page, ImageChunkEvent? event) {
    double b = 0;
    if (event != null && event.expectedTotalBytes != null) {
      b = event.cumulativeBytesLoaded / event.expectedTotalBytes!;
    }
    return Stack(
      children: [
        Positioned.fill(
            child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: b,
          child: Container(color: Colors.grey.withOpacity(0.6)),
        )),
        Positioned.fill(
            child: Center(
                child: Text(
          "${(b * 100).toInt()}",
          style: Theme.of(context)
              .textTheme
              .caption!
              .copyWith(color: Colors.white, fontSize: 8),
        )))
      ],
    );
  }

  Widget readerError(
    BuildContext context,
    int index,
    Object error,
    StackTrace? stackTrace,
  ) {
    return Container(
      color: Colors.redAccent.withOpacity(0.05),
      padding: EdgeInsets.all(32),
      child: Center(child: Text("$error")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Material(
      color: Colors.white,
      child: Stack(
        children: [
          Positioned.fill(
            child: Reader(
              padding: padding.copyWith(
                bottom: padding.bottom + 70,
              ),
              errorBuilder: readerError,
              loadingBuilder: readerLoading,
              backgroundDecoration: BoxDecoration(color: Colors.white),
              controller: controller,
              imageLoader: (context, page, StreamController<ReaderImageChunkEvent> chunkEvents) async {
                // return NetworkImageQuickSize(imageUrls[page],
                //     onImageSize: (size) {
                //       controller.setImageSize(page, size.width, size.height);
                //       // Theme.of(context).textTheme.subtitle1.copyWith()
                //     });
              },
            ),
          ),
          // Positioned(
          //   bottom: 0,
          //   left: 0,
          //   right: 0,
          //   child: ReaderThumbnailBar(
          //     controller: controller,
          //     barHeight: 70,
          //     imageBuilder: (BuildContext context, int page) async {
          //       return NetworkImageQuickSize(thumbnailUrls[page],
          //           onImageSize: (size) {
          //         controller.setImageSize(page, size.width, size.height);
          //       });
          //     },
          //     loadingBuilder: thumbnailLoading,
          //     frameBuilder: thumbnailFrame,
          //   ),
          // ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: debugPanel(),
          )
        ],
      ),
    );
  }
}
