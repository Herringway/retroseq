module sseq.ndsstdheader;

import sseq.common;

struct NDSStdHeader
{
	byte[4] type;
	uint magic;

	void Read(ref PseudoFile file) {
		file.ReadLE(this.type);
		this.magic = file.ReadLE!uint();
		file.ReadLE!uint(); // file size
		file.ReadLE!ushort(); // structure size
		file.ReadLE!ushort(); // # of blocks
	}
	void Verify(const string typeToCheck, uint magicToCheck) {
		if (!VerifyHeader(this.type, typeToCheck) || this.magic != magicToCheck)
			throw new Exception("NDS Standard Header for " ~ typeToCheck ~ " invalid");
	}
};
