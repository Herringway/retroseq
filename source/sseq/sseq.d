module sseq.sseq;

import sseq.sbnk;
import sseq.infoentry;
import sseq.ndsstdheader;
import sseq.common;

struct SSEQ
{
	string filename;
	ubyte[] data;

	const(SBNK) *bank;
	INFOEntrySEQ info;

	this(const string fn) @safe {
		filename = fn;
	}

	void Read(ref PseudoFile file) @safe {
		uint startOfSSEQ = file.pos;
		NDSStdHeader header;
		header.Read(file);
		header.Verify("SSEQ", 0x0100FEFF);
		byte[4] type;
		file.ReadLE(type);
		if (!VerifyHeader(type, "DATA"))
			throw new Exception("SSEQ DATA structure invalid");
		uint size = file.ReadLE!uint();
		uint dataOffset = file.ReadLE!uint();
		this.data.length = size - 12;
		file.pos = startOfSSEQ + dataOffset;
		file.ReadLE(this.data);
	}
};
