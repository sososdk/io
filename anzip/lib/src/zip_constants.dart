/// Temporary spanning marker.
const temspmaker = 0x30304b50; // See APPNOTE.TXT 8.5.4

/// Local file (LOC) header signature.
const locsig = 0x04034b50; // "PK\003\004"

/// Extra local (EXT) header signature.
const extsig = 0x08074b50; // "PK\007\008"

/// Central directory (CEN) header signature.
const censig = 0x02014b50; // "PK\001\002"

/// End of central directory (END) header signature.
const endsig = 0x06054b50; // "PK\005\006"

// ZIP64 end of central directory locator (END) header signature.
const zip64endsig = 0x07064b50;

// ZIP64 central directory (CEN) header signature.
const zip64censig = 0x06064b50;

/// digital signature.
const digsig = 0x05054b50;

/// Local file (LOC) header size in bytes (including signature).
const lochdr = 30;

/// Extra local (EXT) header size in bytes (including signature).
const exthdr = 16;

/// Central directory (CEN) header size in bytes (including signature).
const cenhdr = 46;

/// End of central directory (END) header size in bytes (including signature).
const endhdr = 22;

/// Local file (LOC) header version needed to extract field offset.
const locver = 4;

/// Local file (LOC) header general purpose bit flag field offset.
const locflg = 6;

/// Local file (LOC) header compression method field offset.
const lochow = 8;

/// Local file (LOC) header modification time field offset.
const loctim = 10;

/// Local file (LOC) header uncompressed file crc-32 value field offset.
const loccrc = 14;

/// Local file (LOC) header compressed size field offset.
const locsiz = 18;

/// Local file (LOC) header uncompressed size field offset.
const loclen = 22;

/// Local file (LOC) header filename length field offset.
const locnam = 26;

/// Local file (LOC) header extra field length field offset.
const locext = 28;

/// Extra local (EXT) header uncompressed file crc-32 value field offset.
const extcrc = 4;

/// Extra local (EXT) header compressed size field offset.
const extsiz = 8;

/// Extra local (EXT) header uncompressed size field offset.
const extlen = 12;

/// Central directory (CEN) header version made by field offset.
const cenvem = 4;

/// Central directory (CEN) header version needed to extract field offset.
const cenver = 6;

/// Central directory (CEN) header encrypt, decrypt flags field offset.
const cenflg = 8;

/// Central directory (CEN) header compression method field offset.
const cenhow = 10;

/// Central directory (CEN) header modification time field offset.
const centim = 12;

/// Central directory (CEN) header uncompressed file crc-32 value field offset.
const cencrc = 16;

/// Central directory (CEN) header compressed size field offset.
const censiz = 20;

/// Central directory (CEN) header uncompressed size field offset.
const cenlen = 24;

/// Central directory (CEN) header filename length field offset.
const cennam = 28;

/// Central directory (CEN) header extra field length field offset.
const cenext = 30;

/// Central directory (CEN) header comment length field offset.
const cencom = 32;

/// Central directory (CEN) header disk number start field offset.
const cendsk = 34;

/// Central directory (CEN) header internal file attributes field offset.
const cenatt = 36;

/// Central directory (CEN) header external file attributes field offset.
const cenatx = 38;

/// Central directory (CEN) header LOC header offset field offset.
const cenoff = 42;

/// End of central directory (END) header number of entries on this disk field offset.
const endsub = 8;

/// End of central directory (END) header total number of entries field offset.
const endtot = 10;

/// End of central directory (END) header central directory size in bytes field offset.
const endsiz = 12;

/// End of central directory (END) header offset for the first CEN header field offset.
const endoff = 16;

/// End of central directory (END) header zip file comment length field offset.
const endcom = 20;

/// aes extra data record.
const aesextdatarec = 0x9901;

/// zip64 extra field signature.
const zip64extsig = 0x0001;

/// zip64 size limit.
const zip64sizelimit = 0xFFFFFFFF;

/// zip64 number of entries limit.
const zip64numlimit = 0xffff;

/// max comment size.
const maxCommentSize = 0xffff;

/// aes auth length
const aesAuthLength = 10;

/// aes password verifier length
const aesVerifierLength = 2;

/// aes block size
const aesBlockSize = 16;

/// std dec hdr size
const stdDecHdrSize = 12;
