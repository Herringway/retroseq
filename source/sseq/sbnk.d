module sseq.sbnk;

import sseq.swar;
import sseq.infoentry;
import sseq.ndsstdheader;
import sseq.common;

struct SBNKInstrumentRange
{
	ubyte lowNote;
	ubyte highNote;
	ushort record;
	ushort swav;
	ushort swar;
	ubyte noteNumber;
	ubyte attackRate;
	ubyte decayRate;
	ubyte sustainLevel;
	ubyte releaseRate;
	ubyte pan;

	this(ubyte lowerNote, ubyte upperNote, int recordType) @safe {
		lowNote = lowerNote;
		highNote = upperNote;
		record = cast(ushort)recordType;
	}

	void Read(ref PseudoFile file) @safe {
		this.swav = file.ReadLE!ushort();
		this.swar = file.ReadLE!ushort();
		this.noteNumber = file.ReadLE!ubyte();
		this.attackRate = file.ReadLE!ubyte();
		this.decayRate = file.ReadLE!ubyte();
		this.sustainLevel = file.ReadLE!ubyte();
		this.releaseRate = file.ReadLE!ubyte();
		this.pan = file.ReadLE!ubyte();
	}
};

struct SBNKInstrument
{
	ubyte record;
	SBNKInstrumentRange[] ranges;

	void Read(ref PseudoFile file, uint startOffset) @safe {
		this.record = file.ReadLE!ubyte();
		ushort offset = file.ReadLE!ushort();
		file.ReadLE!ubyte();
		uint endOfInst = file.pos;
		file.pos = startOffset + offset;
		if (this.record)
		{
			if (this.record == 16)
			{
				ubyte lowNote = file.ReadLE!ubyte();
				ubyte highNote = file.ReadLE!ubyte();
				ubyte num = cast(ubyte)(highNote - lowNote + 1);
				for (ubyte i = 0; i < num; ++i)
				{
					ushort thisRecord = file.ReadLE!ushort();
					auto range = SBNKInstrumentRange(cast(ubyte)(lowNote + i), cast(ubyte)(lowNote + i), thisRecord);
					range.Read(file);
					this.ranges ~= range;
				}
			}
			else if (this.record == 17)
			{
				ubyte[8] thisRanges;
				file.ReadLE(thisRanges);
				ubyte i = 0;
				while (i < 8 && thisRanges[i])
				{
					ushort thisRecord = file.ReadLE!ushort();
					ubyte lowNote = i ? cast(ubyte)(thisRanges[i - 1] + 1) : 0;
					ubyte highNote = thisRanges[i];
					auto range = SBNKInstrumentRange(lowNote, highNote, thisRecord);
					range.Read(file);
					this.ranges ~= range;
					++i;
				}
			}
			else
			{
				auto range = SBNKInstrumentRange(0, 127, this.record);
				range.Read(file);
				this.ranges ~= range;
			}
		}
		file.pos = endOfInst;
	}
};

struct SBNK
{
	string filename;
	SBNKInstrument[] instruments;

	const(SWAR)*[4] waveArc;
	INFOEntryBANK info;

	this(const ref string fn) @safe {
		filename = fn;
	}
	this(ref SBNK sbnk) @safe {
		filename = sbnk.filename;
		instruments = sbnk.instruments;
		info = sbnk.info;
	}

	void Read(ref PseudoFile file) @safe {
		uint startOfSBNK = file.pos;
		NDSStdHeader header;
		header.Read(file);
		header.Verify("SBNK", 0x0100FEFF);
		byte[4] type;
		file.ReadLE(type);
		if (!VerifyHeader(type, "DATA"))
			throw new Exception("SBNK DATA structure invalid");
		file.ReadLE!uint(); // size
		uint[8] reserved;
		file.ReadLE(reserved);
		uint count = file.ReadLE!uint();
		this.instruments.length = count;
		for (uint i = 0; i < count; ++i)
			this.instruments[i].Read(file, startOfSBNK);
	}
};
