import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:collection/collection.dart';


class ReaderImageSize extends Size {
  final int index;

  const ReaderImageSize(this.index, double width, double height)
      : super(width, height);

  ReaderImageSize.fromSize(this.index, Size size) : super.copy(size);

  @override
  String toString() => "$index: ${super.toString()}";
}

class ReaderPageInfo {
  final Set<int> page;
  final Set<int> index;
  final int? subPage;


  List<int> get indexList =>
      index.toList()
        ..sort();

  List<int> get pageList =>
      page.toList()
        ..sort();


  ReaderPageInfo(this.page, this.index, [this.subPage]);

  bool get isAllEmpty => index.isEmpty || page.isEmpty;

  bool get isNotEmpty => !isAllEmpty;

  bool get isSingle => index.length == 1 && page.length == 1;

  bool get isSplit => index.length > 1 && page.length == 1;

  bool get isDual => index.length == 1 && page.length > 1;

  copyWith({Set<int>? page, Set<int>? index, int? subPage}) {
    return ReaderPageInfo(
      page ?? {...this.page},
      index ?? {...this.index},
      subPage ?? this.subPage,
    );
  }

  copyWithSubPageFromIndex(int index) {
    var subPage = indexList.indexOf(index);
    if (subPage == -1) subPage = 0;
    return ReaderPageInfo(
        {...page},
        {...this.index},
        subPage
    );
  }


  bool equalsIgnoreSubPage(ReaderPageInfo? other) {
    if (other == null) return false;
    return Object.hashAllUnordered(page) ==
        Object.hashAllUnordered(other.page) &&
        Object.hashAllUnordered(index) ==
            Object.hashAllUnordered(other.index);
  }

  @override
  int get hashCode =>
      Object.hashAllUnordered(page) ^ Object.hashAllUnordered(index) ^ subPage
          .hashCode;

  @override
  operator ==(Object other) {
    if (other is ReaderPageInfo) {
      return Object.hashAllUnordered(page) ==
          Object.hashAllUnordered(other.page) &&
          Object.hashAllUnordered(index) ==
              Object.hashAllUnordered(other.index) && subPage == other.subPage;
    }
    return false;
  }

  @override
  String toString() =>
      "<P:${page} I:${index}${subPage == null ? "" : "S: $subPage"}>";
}

class ReaderController extends ChangeNotifier {
  ItemScrollController? _itemScrollController;
  ItemPositionsListener? _itemPositionsListener;
  PageController? _pageController;

  Map<String, Future<ImageProvider>> providerCache = {};

  final int initialPage;
  final bool keepPage;

  int get currentSubPage => currentPageNumber.subPage ?? 0;

  late ReaderPageInfo _currentPageNumber;

  ReaderPageInfo get currentPageNumber => _currentPageNumber;

  int get currentPage => currentPageNumber.page.firstOrNull ?? 0;

  set currentPageNumber(ReaderPageInfo currentPageNumber) {
    _currentPageNumber = currentPageNumber;
    if (currentPageNumber.isNotEmpty) {
      _currentPageNumberCtrl.sink.add(currentPageNumber);
    }
  }

  final StreamController<
      ReaderPageInfo> _currentPageNumberCtrl = StreamController.broadcast();

  Stream<ReaderPageInfo> get currentPageNumberStream =>
      _currentPageNumberCtrl.stream;

  Stream<int> get currentPageStream =>
      _currentPageNumberCtrl.stream.map((event) => event.page.firstOrNull ?? 0);

  final double viewportFraction;

  final int pageCount;

  late bool _continuous;

  late bool _dualLandscapeAlone;

  bool get dualLandscapeAlone => _dualLandscapeAlone;

  set dualLandscapeAlone(bool dualLandscapeAlone) {
    if (_dualLandscapeAlone == dualLandscapeAlone) return;
    _dualLandscapeAlone = dualLandscapeAlone;
    buildPageNumberData();
  }

  late bool _landscapeSplit;

  bool get landscapeSplit => _landscapeSplit;

  set landscapeSplit(bool landscapeSplit) {
    if (_landscapeSplit == landscapeSplit) return;
    _landscapeSplit = landscapeSplit;
    buildPageNumberData();
  }

  bool get continuous => _continuous;

  set continuous(bool continuous) {
    final nowPage = currentPage;
    if (_continuous == continuous) return;
    _continuous = continuous;
    buildPageNumberData(noRefresh: true);
    _resetPageController(pageToIndex(nowPage));
    _stateChangeCtrl.add(null);
  }

  late bool _dual;

  bool get dual => _dual;

  set dual(bool dual) {
    if (_dual == dual) return;
    _dual = dual;
    buildPageNumberData();
  }

  late bool _dualFirstAlone;

  bool get dualFirstAlone => _dualFirstAlone;

  set dualFirstAlone(bool dualFirstAlone) {
    if (_dualFirstAlone == dualFirstAlone) return;
    _dualFirstAlone = dualFirstAlone;
    buildPageNumberData();
  }

  bool get reverse {
    return readDirection == TextDirection.rtl;
  }

  bool get horizontal {
    if (scrollDirection == null) {
      return !continuous;
    }
    return scrollDirection == Axis.horizontal;
  }

  TextDirection readDirection;

  bool get isRtl => readDirection == TextDirection.rtl;

  Axis? scrollDirection;

  bool get isScrollMode => _itemScrollController?.isAttached ?? false;

  bool get isPageMode => !isScrollMode;

  int? _itemCount;

  int get itemCount {
    if (_itemCount != null) return _itemCount!;
    return pageCount;
  }

  final Map<int, ReaderImageSize> imageSize = {};
  final Map<int, ReaderImageSize> thumbnailSize = {};
  ReaderController({
    required this.pageCount,
    this.initialPage = 0,
    this.keepPage = true,
    this.viewportFraction = 1.0,
    bool continuous = false,
    bool dual = false,
    bool dualFirstAlone = false,
    bool dualLandscapeAlone = false,
    bool landscapeSplit = false,
    this.readDirection = TextDirection.rtl,
    this.scrollDirection,
  }) : super() {
    assert(initialPage < pageCount);
    _dual = dual;
    _dualLandscapeAlone = dualLandscapeAlone;
    _dualFirstAlone = dualFirstAlone;
    _continuous = continuous;
    _landscapeSplit = landscapeSplit;
    currentPageNumber = ReaderPageInfo({0}, {0});
    buildPageNumberData();

    // todo: 销毁
    super.addListener(() {
      final index = currentIndex;
      if (_lastCurrentIndex == index) return;
      _lastCurrentIndex = index;
      if (index == null) return;
      final pageNumber = pageNumberIndexMap[currentIndex];
      if (pageNumber == null) return;
      final indexList = pageNumber.indexList;
      final subPage = indexList.indexOf(index);
      final newPageInfo = pageNumber.copyWith(subPage: subPage);
      if (currentPageNumber == newPageInfo) return;
      currentPageNumber = newPageInfo;
      print("current: $currentPageNumber");
    });
  }

  final StreamController _stateChangeCtrl = StreamController.broadcast();

  Stream get stateChange => _stateChangeCtrl.stream;

  final StreamController<ReaderImageSize> _imageSizeChangeCtrl =
  StreamController.broadcast();

  Stream<ReaderImageSize> get imageSizeChange => _imageSizeChangeCtrl.stream;

  ReaderImageSize placeholderSize = const ReaderImageSize(-1, 351, 500); // 在图片未加载时候默认展示尺寸. 103x182
  double? modeRatio;

  List<ReaderPageInfo> pageNumberList = [];
  Map<int, ReaderPageInfo> pageNumberIndexMap = {};
  Map<int, ReaderPageInfo> pageNumberPageMap = {};


  double getPageWeight(int page) {
    late double ratio;
    if (imageSize[page] == null) {
      ratio = modeRatio ?? 1.0;
    } else {
      ratio = imageSize[page]!.aspectRatio;
    }
    if (dual) {
      if (page == 0 && dualFirstAlone) return 1;
      if (ratio > 1 && dualLandscapeAlone) return 1;
      return 0.5;
    }
    if (ratio > 1 && landscapeSplit) return 2;
    return 1;
  }

  void buildPageNumberData({noRefresh = false}) {
    pageNumberList = [];
    pageNumberIndexMap = {};
    pageNumberPageMap = {};
    double total = 0;
    ReaderPageInfo next = ReaderPageInfo({}, {});
    for (int page = 0; page < pageCount; page++) {
      final weight = getPageWeight(page);
      if (weight >= 1 && next.isNotEmpty) {
        pageNumberList.add(next);
        total = total.ceilToDouble();
        next = ReaderPageInfo({}, {});
      }
      next.page.add(page);
      pageNumberPageMap[page] = next;
      next.index.add(total.floor());
      pageNumberIndexMap[total.floor()] = next;
      if (weight > 1) {
        next.index.add(total.floor() + 1);
        pageNumberIndexMap[total.floor() + 1] = next;
      }
      total += weight;
      if (total % 1 == 0) {
        pageNumberList.add(next);
        next = ReaderPageInfo({}, {});
      }
    }
    final count = total.ceil();
    bool change = false;
    if (count != _itemCount) {
      _itemCount = count;
      change = true;
    }

    if (currentPageNumber.isSplit && pageNumberPageMap[currentPage]!.isSplit) {
      currentPageNumber = pageNumberPageMap[currentPage]!.copyWith(
          subPage: currentPageNumber.subPage);
    } else {
      currentPageNumber = pageNumberPageMap[currentPage]!.copyWith(subPage: 0);
    }

    if (!currentPageNumber.equalsIgnoreSubPage(pageNumberPageMap[currentPage])) {
      print("buildPageNumberData jump");
      jumpToPage(currentPage);
      change = true;
    }
    if (change && !noRefresh) {
      print("change _stateChangeCtrl");
      _stateChangeCtrl.add(null);
    }
  }

  calculationModeRatio() {
    // 统计众数尺寸
    final ratioList = [...imageSize.values, ...thumbnailSize.values]
        .map((e) => ((e.width / e.height) * 100).roundToDouble() / 100);

    final Map<double, int> statistics = {};
    for (var e in ratioList) {
      statistics[e] = (statistics[e] ?? 0) + 1;
    }
    int max = 0;
    List<double> mode = [];
    for (double key in statistics.keys) {
      if (statistics[key]! > max) {
        max = statistics[key]!;
        mode = [key];
      } else if (statistics[key]! == max) {
        mode.add(key);
      }
    }

    if(mode.length == statistics.length) return;

    if(modeRatio != mode.first) {
      print(mode);
      print(statistics);
      modeRatio = mode.first;
    }

    placeholderSize = ReaderImageSize(-1, (modeRatio ?? 1.0) * 500, 500);
  }


  List<Size?> getMultipleImageSize(List<int> indexList) {
    return indexList.map((e) => imageSize[e]).toList();
  }

  Stream<ReaderImageSize> getImageSizeStream(int index) {
    return imageSizeChange.where((event) => event.index == index);
  }

  Stream<List<Size?>> getMultipleImageSizeStream(List<int> indexList) {
    return imageSizeChange
        .where((event) => indexList.contains(event.index))
        .map((event) => indexList.map((e) => imageSize[e]).toList());
  }

  double getImageRatio(int index) {
    if (imageSize.containsKey(index)) {
      return imageSize[index]!.aspectRatio;
    }
    return modeRatio ?? placeholderSize.aspectRatio;
  }

  ReaderImageSize getImageSize(int page) {
    return imageSize[page] ?? thumbnailSize[page] ?? placeholderSize;
  }

  setImageSize(int page, double width, double height, [bool isThumbnail = false]) {
    final sizeMap = isThumbnail ? thumbnailSize : imageSize;
    if (sizeMap[page] != null) {
      if (sizeMap[page]!.width == width &&
          sizeMap[page]!.height == height) return;
    }
    // print("setImageSize index: $page, width: $width, height: $height, isThumbnail: $isThumbnail");
    sizeMap[page] = ReaderImageSize(page, width, height);
    _imageSizeChangeCtrl.add(getImageSize(page));
    if (sizeMap.length > 6) {
      // 大于4张开始计算
      calculationModeRatio();
    }
    buildPageNumberData();
  }

  ReaderPageInfo getPagesFromIndex(int index) {
    final pageInfo = pageNumberIndexMap[index];
    int subPage = 0;
    if (pageInfo!.isSplit) {
      subPage = pageInfo.indexList.indexOf(index);
    }
    return pageInfo.copyWith(subPage: subPage);
  }

  int pageToIndex(int page) {
    if (pageNumberPageMap[page] == null) return 0;
    final indexList = pageNumberPageMap[page]!.index.toList();
    if (indexList.length > currentSubPage) return indexList[currentSubPage];
    return indexList.first;
  }

  ItemScrollController getItemScrollController() {
    if (_itemScrollController != null) return _itemScrollController!;
    _itemScrollController = ItemScrollController();
    return _itemScrollController!;
  }

  ItemPositionsListener getItemPositionsListener() {
    if (_itemPositionsListener != null) return _itemPositionsListener!;
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener!.itemPositions.addListener(notifyListeners);
    return _itemPositionsListener!;
  }

  PageController _resetPageController(int index) {
    if (_pageController != null) {
      _pageController!.removeListener(notifyListeners);
    }
    _pageController = PageController(
        initialPage: index,
        viewportFraction: viewportFraction,
        keepPage: keepPage);
    _pageController!.addListener(notifyListeners);
    return _pageController!;
  }

  PageController getPageController([int? resetPage]) {
    if (_pageController != null && resetPage == null) return _pageController!;

    if (_pageController != null) {
      _pageController!.removeListener(notifyListeners);
    }

    _pageController = PageController(
        initialPage: resetPage ?? initialPage,
        viewportFraction: viewportFraction,
        keepPage: keepPage);
    _pageController!.addListener(notifyListeners);
    return _pageController!;
  }

  int? _lastCurrentIndex;

  int? get currentIndex {
    if (isPageMode) return _pageController?.page?.round();
    final value = _itemPositionsListener!.itemPositions.value.toList();
    if (value.isEmpty) return null;
    value.sort((a, b) {
      getVisibility(ItemPosition v) {
        final w = v.itemTrailingEdge - v.itemLeadingEdge;
        final l = max(0.0, v.itemLeadingEdge);
        final r = min(1.0, v.itemTrailingEdge);
        final w2 = (r - l);
        final size = w2 / w;
        return size;
      }
      final va = (getVisibility(a) * 100).toInt();
      final vb = (getVisibility(b) * 100).toInt();
      if (va == vb) {
        return a.index - b.index;
      }
      return vb - va;
    });
    return value.first.index;
  }

  List<ItemPosition>? get pages {
    if (isPageMode) {
      if (_pageController?.page == null) return null;
      return [
        ItemPosition(
            index: _pageController!.page!.round(),
            itemLeadingEdge: 0,
            itemTrailingEdge: 0)
      ];
    }
    return _itemPositionsListener!.itemPositions.value.toList();
  }

  Future<void> nextIndex({required Duration duration, required Curve curve}) {
    if (currentIndex == null) return Future.value();
    return animateToPage(currentIndex! + 1, duration: duration, curve: curve);
  }

  void jumpToPage(int page) {
    final pageNumber = pageNumberPageMap[page];
    if (pageNumber == null) return;
    // todo 拆分页面需要考虑跳转到哪半边;
    jumpToIndex(pageNumber.index.first);
  }

  void jumpToIndex(int index) {
    print("jump to index: $index");
    if (_itemScrollController?.isAttached ?? false) {
      _itemScrollController?.jumpTo(index: index);
    }
    if (_pageController?.hasClients ?? false) {
      return _pageController?.jumpToPage(index);
    }
  }

  Future<void> animateToPage(int page,
      {required Duration duration, required Curve curve}) {
    final pageNumber = pageNumberPageMap[page];
    if (pageNumber == null) return Future.value(null);
    // todo 拆分页面需要考虑跳转到哪半边;
    return animateToIndex(
        pageNumber.index.first, duration: duration, curve: curve);
  }

  Future<void> animateToIndex(int index,
      {required Duration duration, required Curve curve}) {
    if (isPageMode) {
      return _pageController!
          .animateToPage(index, duration: duration, curve: curve);
    }
    return _itemScrollController!
        .scrollTo(index: index, duration: duration, curve: curve);
  }

  printPagesDebug() {
    final direction = List.generate(itemCount, (index) {
      if (imageSize[index] == null) return "?";
      return imageSize[index]!.aspectRatio > 1 ? "L" : "P";
    }).join(" ");
    print("direction: $direction");
  }

  @override
  dispose() {
    super.dispose();
    _imageSizeChangeCtrl.close();
    _stateChangeCtrl.close();
    _currentPageNumberCtrl.close();
    _pageController?.dispose();
  }

}

/*
* L(landscape 宽高比>1) P(portrait 宽高比<=1)
* 未知的尺寸图片默认为 P
*
* 横屏双页模式 两个P拼接
* 外部页码: 0 1 2 3 4 5 6 7 8 9 10 11
* 图片尺寸: L P P P P P L P P P P  L
* 图片尺寸: L P ? ? ? P L P P P P  L
* 列表下表: 0 1   2   3 4 5   6    7
*
*
* 竖屏自动拆分模式 L拆分两半分开显示
* 外部页码: 0 . 1 . 2 3 . 4 5 .
* 图片尺寸: L . L . P L . P L .
* 列表下标: 0 1 2 3 4 5 6 7 8 9
*
* TODO: 计算列表总长度
* TODO: 外部页码与内部页码转换
*
* */
