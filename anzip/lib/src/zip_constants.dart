/// Temporary spanning marker. http://www.pkware.com/documents/casestudies/APPNOTE.TXT
const kTemspmaker = [0x50, 0x4b, 0x30, 0x30]; // 0x30304b50 "PK\030\030"

/// Local file (LOC) header signature.
const kLocsig = [0x50, 0x4b, 0x03, 0x04]; // 0x04034b50 "PK\003\004"

/// Extra local (EXT) header signature.
const kExtsig = [0x50, 0x4b, 0x07, 0x08]; // 0x08074b50 "PK\007\008"

/// Central directory (CEN) header signature.
const kCensig = [0x50, 0x4b, 0x01, 0x02]; // 0x02014b50 "PK\001\002"

/// End of central directory (END) header signature.
const kEndsig = [0x50, 0x4b, 0x05, 0x06]; // 0x06054b50 "PK\005\006"

// ZIP64 end of central directory locator (END) header signature.
const kZip64endsig = [0x50, 0x4b, 0x06, 0x07]; // 0x07064b50;

// ZIP64 central directory (CEN) header signature.
const kZip64censig = [0x50, 0x4b, 0x06, 0x06]; // 0x06064b50;

/// digital signature.
const kDigsig = [0x50, 0x4b, 0x06, 0x05]; // 0x05054b50;

/// Local file (LOC) header size in bytes (including signature).
const kLochdr = 30;

/// Extra local (EXT) header size in bytes (including signature).
const kExthdr = 16;

/// Central directory (CEN) header size in bytes (including signature).
const kCenhdr = 46;

/// End of central directory (END) header size in bytes (including signature).
const kEndhdr = 22;

/// Local file (LOC) header version needed to extract field offset.
const kLocver = 4;

/// Local file (LOC) header general purpose bit flag field offset.
const kLocflg = 6;

/// Local file (LOC) header compression method field offset.
const kLochow = 8;

/// Local file (LOC) header modification time field offset.
const kLoctim = 10;

/// Local file (LOC) header uncompressed file crc-32 value field offset.
const kLoccrc = 14;

/// Local file (LOC) header compressed size field offset.
const kLocsiz = 18;

/// Local file (LOC) header uncompressed size field offset.
const kLoclen = 22;

/// Local file (LOC) header filename length field offset.
const kLocnam = 26;

/// Local file (LOC) header extra field length field offset.
const kLocext = 28;

/// Extra local (EXT) header uncompressed file crc-32 value field offset.
const kExtcrc = 4;

/// Extra local (EXT) header compressed size field offset.
const kExtsiz = 8;

/// Extra local (EXT) header uncompressed size field offset.
const kExtlen = 12;

/// Central directory (CEN) header version made by field offset.
const kCenvem = 4;

/// Central directory (CEN) header version needed to extract field offset.
const kCenver = 6;

/// Central directory (CEN) header encrypt, decrypt flags field offset.
const kCenflg = 8;

/// Central directory (CEN) header compression method field offset.
const kCenhow = 10;

/// Central directory (CEN) header modification time field offset.
const kCentim = 12;

/// Central directory (CEN) header uncompressed file crc-32 value field offset.
const kCencrc = 16;

/// Central directory (CEN) header compressed size field offset.
const kCensiz = 20;

/// Central directory (CEN) header uncompressed size field offset.
const kCenlen = 24;

/// Central directory (CEN) header filename length field offset.
const kCennam = 28;

/// Central directory (CEN) header extra field length field offset.
const kCenext = 30;

/// Central directory (CEN) header comment length field offset.
const kCencom = 32;

/// Central directory (CEN) header disk number start field offset.
const kCendsk = 34;

/// Central directory (CEN) header internal file attributes field offset.
const kCenatt = 36;

/// Central directory (CEN) header external file attributes field offset.
const kCenatx = 38;

/// Central directory (CEN) header LOC header offset field offset.
const kCenoff = 42;

/// End of central directory (END) header number of entries on this disk field offset.
const kEndsub = 8;

/// End of central directory (END) header total number of entries field offset.
const kEndtot = 10;

/// End of central directory (END) header central directory size in bytes field offset.
const kEndsiz = 12;

/// End of central directory (END) header offset for the first CEN header field offset.
const kEndoff = 16;

/// End of central directory (END) header zip file comment length field offset.
const kEndcom = 20;

/// aes extra data record.
const kAesextdatarec = [0x01, 0x99];

/// zip64 extra field signature.
const kZip64extsig = [0x01, 0x00];

/// zip64 size limit.
const kZip64sizelimit = 0xffffffff;

/// zip64 number of entries limit.
const kZip64numlimit = 0xffff;

/// max comment size.
const kMaxCommentSize = 0xffff;

/// max filename size.
const kMaxFilenameSize = 0xffff;

/// aes auth length
const kAesAuthLength = 10;

/// aes password verifier length
const kAesVerifierLength = 2;

/// aes block size
const kAesBlockSize = 16;

/// std dec hdr size
const kStdDecHdrSize = 12;
