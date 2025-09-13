///
module retroseq.sseq.sseq;

import retroseq.sseq.sbnk;
import retroseq.sseq.infosection;
import retroseq.sseq.ndsstdheader;
import retroseq.sseq.common;

///
struct SSEQ {
	///
	static struct DataHeader {
		align(1):
		char[4] type; ///
		uint fileSize; ///
		uint dataOffset; ///
	}
	NDSStdHeader header; ///
	DataHeader dataHeader; ///
	const(char)[] filename; ///
	const(ubyte)[] data; ///

	INFOEntrySEQ info; ///

	///
	this(const char[] fn) @safe {
		filename = fn;
	}
}
