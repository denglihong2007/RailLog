import 'package:dio/dio.dart';

enum CtPhotoSearchFilter { model, station, train }

class CtPhoto {
  const CtPhoto({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.trainNumber,
    required this.stationName,
    required this.lineName,
    required this.author,
    required this.shootDate,
    required this.viewsCount,
    required this.likesCount,
  });

  final int id;
  final String title;
  final String thumbnailUrl;
  final String trainNumber;
  final String stationName;
  final String lineName;
  final String author;
  final String shootDate;
  final int viewsCount;
  final int likesCount;

  factory CtPhoto.fromJson(Map<String, dynamic> json) => CtPhoto(
    id: _int(json['photo_id']),
    title: _string(json['title']),
    thumbnailUrl: _string(json['thumbnail_url']),
    trainNumber: _string(json['train_number']),
    stationName: _string(json['station_name']),
    lineName: _string(json['line_name']),
    author: _string((json['author'] as Map?)?['nickname']),
    shootDate: _string(json['shoot_date']),
    viewsCount: _int(json['views_count']),
    likesCount: _int(json['likes_count']),
  );
}

class CtPhotoSearchResult {
  const CtPhotoSearchResult({
    required this.photos,
    required this.page,
    required this.pages,
  });

  final List<CtPhoto> photos;
  final int page;
  final int pages;
}

class CtPhotoService {
  CtPhotoService._();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://train.idcmoss.cn/api',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
    ),
  );

  static Future<CtPhotoSearchResult> search(
    String keyword, {
    CtPhotoSearchFilter filter = CtPhotoSearchFilter.model,
    int page = 1,
  }) async {
    if (filter != CtPhotoSearchFilter.model) {
      return _searchPhotos(keyword, filter: filter, page: page);
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/model_search.php',
      queryParameters: {'q': keyword.trim(), 'page': page, 'per_page': 20},
    );
    final data = response.data ?? const <String, dynamic>{};
    if (data['success'] != true) {
      throw StateError(
        _string(data['message']).isEmpty ? '照片搜索失败' : _string(data['message']),
      );
    }
    final photos = <CtPhoto>[];
    for (final model in (data['models'] as List? ?? const [])) {
      final modelMap = model is Map
          ? Map<String, dynamic>.from(model)
          : const <String, dynamic>{};
      for (final photo in (modelMap['reference_photos'] as List? ?? const [])) {
        if (photo is Map) {
          photos.add(CtPhoto.fromJson(Map<String, dynamic>.from(photo)));
        }
      }
    }
    return CtPhotoSearchResult(
      photos: photos,
      page: _int(data['page'], fallback: page),
      pages: _int(data['pages'], fallback: page),
    );
  }

  static Future<CtPhotoSearchResult> _searchPhotos(
    String keyword, {
    required CtPhotoSearchFilter filter,
    required int page,
  }) async {
    final parameter = switch (filter) {
      CtPhotoSearchFilter.station => 'station',
      CtPhotoSearchFilter.train => 'train',
      CtPhotoSearchFilter.model => throw ArgumentError.value(filter),
    };
    final response = await _dio.get<Map<String, dynamic>>(
      '/photo_search.php',
      queryParameters: {
        parameter: keyword.trim(),
        'page': page,
        'per_page': 20,
      },
    );
    final data = response.data ?? const <String, dynamic>{};
    if (data['success'] != true) {
      throw StateError(
        _string(data['message']).isEmpty ? '照片搜索失败' : _string(data['message']),
      );
    }
    return CtPhotoSearchResult(
      photos: [
        for (final photo in (data['photos'] as List? ?? const []))
          if (photo is Map) CtPhoto.fromJson(Map<String, dynamic>.from(photo)),
      ],
      page: _int(data['page'], fallback: page),
      pages: _int(data['pages'], fallback: page),
    );
  }
}

String _string(Object? value) => value?.toString().trim() ?? '';
int _int(Object? value, {int fallback = 0}) =>
    int.tryParse(_string(value)) ?? fallback;
