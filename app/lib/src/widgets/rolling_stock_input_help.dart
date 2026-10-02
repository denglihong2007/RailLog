import 'package:flutter/material.dart';
import 'package:raillog/src/widgets/help_dialog.dart';

Future<void> showRollingStockInputHelp(BuildContext context) {
  return showHelpDialog(
    context,
    title: '车型填写说明',
    message:
        '填写规则\n'
        '机车、车底及机车之间使用“+”连接；车型与车号之间使用空格分隔。\n'
        '车号可以省略。同一车型对应多个车号时，使用“&”连接。\n'
        '列车中途改变编组时，不同编组之间使用“/”连接。\n\n'
        '普速列车示例\n'
        'DF11G + 19T\n'
        'HXD1D 0001&0002+WX25T 999318\n'
        'HXD3 0631&0155+SS7D 0044+25G/SS7D 0044+25G\n'
        'HXD1D 0563+25T/HXD1D 0100+25T/NJ2 0071+HXN3 0331+25G\n\n'
        '动车组列车示例\n'
        'CRH380AN\n'
        'CR400BF-BS-5347&5348\n'
        'CR400BF-5033&5034/CRH380B-3772&3627',
  );
}
