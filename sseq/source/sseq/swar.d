module sseq.swar;

import sseq.swav;
import sseq.infosection;
import sseq.ndsstdheader;
import sseq.common;

struct SWAR
{
	static struct DataHeader {
		align(1):
		char[4] type;
		uint fileSize;
		ubyte[32] reserved;
		uint blockCount;
	}
	NDSStdHeader header;
	DataHeader dataHeader;
	const(char)[] filename;
	const(ubyte)[] data;
	SWAV[uint] swavs;

	INFOEntryWAVEARC info;

	this(const char[] fn) @safe {
		filename = fn;
	}
	void loadSWAVs() @safe {
		const offsets = cast(const(uint)[])data[0 .. uint.sizeof * dataHeader.blockCount];
		foreach (idx, offset; offsets) {
			const adjustedOffset = offsets[idx] - NDSStdHeader.sizeof - DataHeader.sizeof;
			auto swavData = data[adjustedOffset .. $];
			swavs.require(cast(uint)idx, (){
				SWAV result;
				result.header = swavData.pop!(SWAV.Header)();
				result.data = decode(swavData, result.header);
				return result;
			}());
		}

	}
	const(SWAV)* opIndex(size_t idx) const @safe {
		return cast(uint)idx in swavs;
	}
}
