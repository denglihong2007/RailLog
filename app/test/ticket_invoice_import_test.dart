import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/ticket_invoice_import_service.dart';

String _invoiceXml({String originalInvoice = ''}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<xbrl xmlns:rai="http://xbrl.mof.gov.cn/taxonomy/2021-11-30/rai">
<rai:TypeOfVoucher contextRef="c">电子发票（铁路电子客票）</rai:TypeOfVoucher>
<rai:ElectronicInvoiceRailwayETicketNumber contextRef="c">26519146543006117611</rai:ElectronicInvoiceRailwayETicketNumber>
<rai:DepartureStation contextRef="c">成都东</rai:DepartureStation>
<rai:DestinationStation contextRef="c">广元</rai:DestinationStation>
<rai:TrainNumber contextRef="c">C5990</rai:TrainNumber>
<rai:TravelDate contextRef="c">2026-07-02</rai:TravelDate>
<rai:DepartureTime contextRef="c">22:24</rai:DepartureTime>
<rai:SeatLevel contextRef="c">二等座</rai:SeatLevel>
<rai:Carriage contextRef="c">03车</rai:Carriage>
<rai:Seat contextRef="c">17F号</rai:Seat>
<rai:Fare contextRef="c">100.00</rai:Fare>
<rai:ETicketNumber contextRef="c">46543A2086062990920912026</rai:ETicketNumber>
<rai:Name contextRef="c">张三</rai:Name>
<rai:NameOfPurchaser contextRef="c">张三</rai:NameOfPurchaser>
${originalInvoice.isEmpty ? '' : '<rai:NumberOfOriginalInvoice contextRef="c">$originalInvoice</rai:NumberOfOriginalInvoice>'}
</xbrl>
''';

Uint8List _buildOfd(String xml) {
  final content = utf8.encode(xml);
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'Doc_0/Attachs/rai_issuer_20260709.xml',
        content.length,
        content,
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Uint8List _buildPdf(String xml) {
  final compressed = ZLibEncoder().encode(utf8.encode(xml));
  final builder = BytesBuilder()
    ..add(utf8.encode('%PDF-1.7\n'))
    ..add(
      utf8.encode(
        '44 0 obj\n'
        '<</Filter/FlateDecode/Length ${compressed.length}/Params<</Size 1024>>'
        '/Type/EmbeddedFile>>\nstream\n',
      ),
    )
    ..add(compressed)
    ..add(utf8.encode('\nendstream\nendobj\n%%EOF\n'));
  return builder.toBytes();
}

void main() {
  group('TicketInvoiceImportService.parseXbrl', () {
    test('maps railway invoice fields into a trip order', () {
      final order = TicketInvoiceImportService.parseXbrl(_invoiceXml());

      expect(order.trainCode, 'C5990');
      expect(order.fromStation, '成都东');
      expect(order.toStation, '广元');
      expect(order.startTime, DateTime(2026, 7, 2, 22, 24));
      expect(order.arriveTime, isNull);
      expect(order.passengerName, '张三');
      expect(order.seatType, '二等座');
      expect(order.coachName, '03');
      expect(order.seatName, '17F');
      expect(order.seatDisplay, '二等座 03车17F');
      expect(order.price, 100);
      expect(order.distance, 0);
      expect(order.statusText, '电子发票');
      expect(order.canImport, isTrue);
    });

    test('treats a credit note as non-importable', () {
      final order = TicketInvoiceImportService.parseXbrl(
        _invoiceXml(originalInvoice: '26519146543006100000'),
      );

      expect(order.statusText, '红字发票');
      expect(order.canImport, isFalse);
    });

    test('rejects data without a travel date', () {
      expect(
        () => TicketInvoiceImportService.parseXbrl(
          '<xbrl><TrainNumber>G1</TrainNumber></xbrl>',
        ),
        throwsA(isA<TicketInvoiceImportException>()),
      );
    });
  });

  group('TicketInvoiceImportService file parsing', () {
    test('reads the XBRL attachment inside an OFD', () {
      final order = TicketInvoiceImportService.parseBytes(
        'invoice.ofd',
        _buildOfd(_invoiceXml()),
      );

      expect(order.trainCode, 'C5990');
      expect(order.fromStation, '成都东');
    });

    test('reads the embedded XBRL attachment inside a PDF', () {
      final order = TicketInvoiceImportService.parseBytes(
        'invoice.pdf',
        _buildPdf(_invoiceXml()),
      );

      expect(order.trainCode, 'C5990');
      expect(order.seatDisplay, '二等座 03车17F');
    });

    test('dedupes the PDF and OFD of the same invoice', () {
      final batch = TicketInvoiceImportService.importFiles([
        InvoiceImportFile(name: 'a.pdf', bytes: _buildPdf(_invoiceXml())),
        InvoiceImportFile(name: 'a.ofd', bytes: _buildOfd(_invoiceXml())),
      ]);

      expect(batch.fileCount, 2);
      expect(batch.orders, hasLength(1));
      expect(batch.failures, isEmpty);
    });

    test('reports unreadable files without dropping the rest', () {
      final batch = TicketInvoiceImportService.importFiles([
        InvoiceImportFile(
          name: 'broken.pdf',
          bytes: Uint8List.fromList([1, 2]),
        ),
        InvoiceImportFile(name: 'ok.ofd', bytes: _buildOfd(_invoiceXml())),
      ]);

      expect(batch.orders, hasLength(1));
      expect(batch.failures, hasLength(1));
      expect(batch.failures.single, contains('broken.pdf'));
    });
  });
}
