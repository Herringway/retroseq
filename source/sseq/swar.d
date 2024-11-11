module sseq.swar;

import sseq.swav;
import sseq.infoentry;
import sseq.ndsstdheader;
import sseq.common;

/*
 * The size has been left out of this structure as it is unused by this player.
 */
struct SWAR
{
	string filename;
	SWAV[uint] swavs;

	INFOEntryWAVEARC info;

	this(const ref string fn) {
		filename = fn;
	}

	void Read(ref PseudoFile file) {
		uint startOfSWAR = file.pos;
		NDSStdHeader header;
		header.Read(file);
		header.Verify("SWAR", 0x0100FEFF);
		byte[4] type;
		file.ReadLE(type);
		if (!VerifyHeader(type, "DATA"))
			throw new Exception("SWAR DATA structure invalid");
		file.ReadLE!uint(); // size
		uint[8] reserved;
		file.ReadLE(reserved);
		uint count = file.ReadLE!uint();
		auto offsets = new uint[](count);
		file.ReadLE(offsets);
		for (uint i = 0; i < count; ++i)
			if (offsets[i])
			{
				file.pos = startOfSWAR + offsets[i];
				this.swavs[i] = SWAV();
				this.swavs[i].Read(file);
			}
	}
};
