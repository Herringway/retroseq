module sseq.sseq;

import sseq.sbnk;
import sseq.infosection;
import sseq.ndsstdheader;
import sseq.common;

struct SSEQ {
	static struct DataHeader {
		align(1):
		char[4] type;
		uint fileSize;
		uint dataOffset;
	}
	NDSStdHeader header;
	DataHeader dataHeader;
	const(char)[] filename;
	const(ubyte)[] data;

	INFOEntrySEQ info;

	this(const char[] fn) @safe {
		filename = fn;
	}
}
