module sseq.infoentry;

import sseq.common;

struct INFOEntrySEQ
{
	ushort fileID;
	ushort bank;
	ubyte vol;

	void Read(ref PseudoFile file) {
		this.fileID = file.ReadLE!ushort();
		file.ReadLE!ushort(); // unknown
		this.bank = file.ReadLE!ushort();
		this.vol = file.ReadLE!ubyte();
		if (!this.vol)
			this.vol = 0x7F; // Prevents nothing for volume
		file.ReadLE!ubyte(); // cpr
		file.ReadLE!ubyte(); // ppr
		file.ReadLE!ubyte(); // ply
	}
};

struct INFOEntryBANK
{
	ushort fileID;
	ushort[4] waveArc;

	void Read(ref PseudoFile file) {
		this.fileID = file.ReadLE!ushort();
		file.ReadLE!ushort(); // unknown
		file.ReadLE(this.waveArc);
	}
};

struct INFOEntryWAVEARC
{
	ushort fileID;

	void Read(ref PseudoFile file) {
		this.fileID = file.ReadLE!ushort();
	}
};
