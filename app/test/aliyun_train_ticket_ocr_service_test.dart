import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/aliyun_train_ticket_ocr_service.dart';
import 'package:raillog/src/services/train_ticket_ocr_models.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  RequestOptions? options;
  Uint8List? requestBytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    if (requestStream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in requestStream) {
        builder.add(chunk);
      }
      requestBytes = builder.takeBytes();
    }
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_RecordingAdapter adapter) => Dio()..httpClientAdapter = adapter;

AliyunTrainTicketOcrService _serviceWith(_RecordingAdapter adapter) =>
    AliyunTrainTicketOcrService(
      dio: _dioWith(adapter),
      clock: () => DateTime.utc(2024, 3, 28, 8, 40, 15),
      nonceGenerator: () => 'nonce-value',
    );

const _credentials = AliyunOcrCredentials(
  accessKeyId: 'testid',
  accessKeySecret: 'testsecret',
);

void main() {
  test('RPC 签名与阿里云文档的 HMAC-SHA1 算法一致', () {
    expect(
      AliyunRpcSignature.sign(
        method: 'POST',
        parameters: const {
          'AccessKeyId': 'testid',
          'Action': 'RecognizeTrainInvoice',
          'Format': 'JSON',
          'SignatureMethod': 'HMAC-SHA1',
          'SignatureNonce': 'nonce-value',
          'SignatureVersion': '1.0',
          'Timestamp': '2024-03-28T08:40:15Z',
          'Version': '2021-07-07',
        },
        accessKeySecret: 'testsecret',
      ),
      'JiIYV8f4ZUjzsVpF95H0csHDA28=',
    );
  });

  test('把图片二进制放进 body，并解析结构化结果', () async {
    final adapter = _RecordingAdapter(
      jsonEncode({
        'RequestId': '43A29C77-405E-4CC0-BC55-EE694AD00655',
        'Data': jsonEncode({
          'data': {
            'departureStation': '苏州站',
            'arrivalStation': '南京南站',
            'trainNumber': 'G7350',
            'departureTime': '2017年08月05日22:09开',
            'seatNumber': '04车13A号',
            'fare': '104.5',
            'seatType': '新空调二等座',
          },
          'ftype': 0,
        }),
      }),
    );

    final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
    final result = await _serviceWith(
      adapter,
    ).recognize(imageBytes, _credentials);

    expect(adapter.requestBytes, imageBytes);
    expect(adapter.options?.uri.host, 'ocr-api.cn-hangzhou.aliyuncs.com');
    expect(
      adapter.options?.uri.queryParameters['Action'],
      'RecognizeTrainInvoice',
    );
    expect(adapter.options?.uri.queryParameters['AccessKeyId'], 'testid');
    expect(
      adapter.options?.uri.queryParameters['Signature'],
      'JiIYV8f4ZUjzsVpF95H0csHDA28=',
    );
    expect(adapter.options?.contentType, 'application/octet-stream');

    expect(result.trainNumber, 'G7350');
    expect(result.fromStation, '苏州站');
    expect(result.toStation, '南京南站');
    expect(result.departureTime, DateTime(2017, 8, 5, 22, 9));
    expect(result.seatType, '二等座');
    expect(result.seatNumber, '04车13A号');
    expect(result.price, 104.5);
  });

  test('错误响应转成可读的异常消息', () async {
    final adapter = _RecordingAdapter(
      jsonEncode({
        'Code': 'SignatureDoesNotMatch',
        'Message': 'Specified signature is not matched with our calculation.',
        'RequestId': 'req-1',
      }),
      statusCode: 400,
    );

    await expectLater(
      _serviceWith(adapter).recognize(Uint8List.fromList([1]), _credentials),
      throwsA(
        isA<TrainTicketOcrException>().having(
          (error) => error.message,
          'message',
          contains('SignatureDoesNotMatch'),
        ),
      ),
    );
  });

  test('未填写密钥时不发请求', () async {
    final adapter = _RecordingAdapter('{}');
    await expectLater(
      _serviceWith(adapter).recognize(
        Uint8List.fromList([1]),
        const AliyunOcrCredentials(accessKeyId: '', accessKeySecret: ''),
      ),
      throwsA(isA<TrainTicketOcrException>()),
    );
    expect(adapter.options, isNull);
  });
}
