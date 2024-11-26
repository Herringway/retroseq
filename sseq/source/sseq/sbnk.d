module sseq.sbnk;

import sseq.swar;
import sseq.infosection;
import sseq.ndsstdheader;
import sseq.common;

struct SBNKInstrumentRange {
	static struct Header {
		align(1):
		ushort swav;
		ushort swar;
		ubyte noteNumber;
		ubyte attackRate;
		ubyte decayRate;
		ubyte sustainLevel;
		ubyte releaseRate;
		ubyte pan;
	}
	ubyte lowNote;
	ubyte highNote;
	ushort record;
	Header header;

	this(ubyte lowerNote, ubyte upperNote, int recordType) @safe {
		lowNote = lowerNote;
		highNote = upperNote;
		record = cast(ushort)recordType;
	}
}

struct SBNKInstrument {
	static struct Record {
		align(1):
		ubyte type;
		ushort offset;
		ubyte reserved;
	}
	Record record;
	SBNKInstrumentRange[] ranges;

	void read(const(ubyte)[] file, Record record) @safe {
		this.record = record;
		if (record.type)
		{
			if (record.type == 16)
			{
				ubyte lowNote = file.pop!ubyte();
				ubyte highNote = file.pop!ubyte();
				ubyte num = cast(ubyte)(highNote - lowNote + 1);
				for (ubyte i = 0; i < num; ++i)
				{
					ushort thisRecord = file.pop!ushort();
					auto range = SBNKInstrumentRange(cast(ubyte)(lowNote + i), cast(ubyte)(lowNote + i), thisRecord);
					range.header = file.pop!(SBNKInstrumentRange.Header)();
					this.ranges ~= range;
				}
			}
			else if (record.type == 17)
			{
				ubyte[8] thisRanges = file.pop!(ubyte[8])();
				ubyte i = 0;
				while (i < 8 && thisRanges[i])
				{
					ushort thisRecord = file.pop!ushort();
					ubyte lowNote = i ? cast(ubyte)(thisRanges[i - 1] + 1) : 0;
					ubyte highNote = thisRanges[i];
					auto range = SBNKInstrumentRange(lowNote, highNote, thisRecord);
					range.header = file.pop!(SBNKInstrumentRange.Header)();
					this.ranges ~= range;
					++i;
				}
			}
			else
			{
				auto range = SBNKInstrumentRange(0, 127, record.type);
				range.header = file.pop!(SBNKInstrumentRange.Header)();
				this.ranges ~= range;
			}
		}
	}
};

struct SBNK {
	static struct DataHeader {
		align(1):
		char[4] type;
		uint fileSize;
		ubyte[32] reserved;
		uint instruments;
	}
	NDSStdHeader header;
	DataHeader dataHeader;
	const(char)[] filename;
	SBNKInstrument[] instruments;

	INFOEntryBANK info;

	this(const char[] fn) @safe {
		filename = fn;
	}

	void read(const(ubyte)[] file) @safe {
		this.instruments.length = dataHeader.instruments;
		const records = cast(const(SBNKInstrument.Record)[])(file[0 .. SBNKInstrument.Record.sizeof * dataHeader.instruments]);
		foreach (idx, ref instrument; instruments) {
			if (records[idx].type == 0) {
				continue;
			}
			instrument.read(file[records[idx].offset - DataHeader.sizeof - NDSStdHeader.sizeof .. $], records[idx]);
		}
	}
};
