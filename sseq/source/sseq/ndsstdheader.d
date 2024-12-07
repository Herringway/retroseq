///
module sseq.ndsstdheader;

import sseq.common;
import std.exception;

///
struct NDSStdHeader {
	align(1):
	byte[4] type; ///
	ushort bom; ///
	ushort version_; ///
	uint size; ///
	ushort headerSize; ///
	ushort blockCount; ///

}
///
void verify(const NDSStdHeader header, const string typeToCheck) @safe {
	enforce((header.type == typeToCheck) && (header.bom == 0xFEFF), "NDS Standard Header for " ~ typeToCheck ~ " invalid");
}
