import 'package:convert/convert.dart';

const _controls = '\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007'
    '\b\t\n\u000b\f\r\u000e\u000f\u0010\u0011'
    '\u0012\u0013\u0014\u0015\u0016\u0017\u0018'
    '\u0019\u001a\u001b\u001c\u001d\u001e\u001f';

/// ASCII characters with control characters. Shared by many code pages.
const _ascii = '$_controls'
    r""" !"#$%&'()*+,-./0123456789:;<=>?"""
    r'@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_'
    '`abcdefghijklmnopqrstuvwxyz{|}~\uFFFD';

const _cp437 = '$_ascii'
    'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐'
    '└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';

/// The cp437 codec
final cp437 = CodePage('cp437', _cp437);
