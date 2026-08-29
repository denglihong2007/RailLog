import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/help_dialog.dart';

Future<void> showRollingStockInputHelp(BuildContext context) {
  return showHelpDialog(
    context,
    title: '车型填写说明',
    message:
        '填写规则\n'
        '机车、车底及机车之间使用“+”连接；车型与车号之间使用空格分隔。\n'
        '车号可以省略。同一车型对应多个车号时，使用“&”连接。\n\n'
        '普速列车示例\n'
        '19T\n'
        'HXD1D 0001&0002+WX25T 999318\n'
        'HXD3CA 0001+SS7D+KD25K 998715\n\n'
        '动车组列车示例\n'
        'CRH380AN\n'
        'CR400BF-BS-5347&5348\n'
        'CR400BF-5033&5034',
  );
}
