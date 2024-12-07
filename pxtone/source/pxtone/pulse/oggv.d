///
module pxtone.pulse.oggv;

version (WithOggVorbis):
import core.stdc.config;
import derelict.vorbis.codec;
import derelict.vorbis.file;

import pxtone.descriptor;
import pxtone.error;
import pxtone.pulse.pcm;

import std.exception;
import std.stdio;

///
struct OVMEM {
	const(ubyte)[] pBuf; /// ogg vorbis-data on memory.s
	int size; ///
	int pos; /// reading position.
}

// 4 callbacks below:

///
private extern (C) size_t vorbisReadCallback(void* p, size_t size, size_t nmemb, void* user) nothrow @trusted {
	return vorbisReadCallback((cast(ubyte*)p)[0 .. size * nmemb], size, nmemb, cast(OVMEM*)user);
}

///
private size_t vorbisReadCallback(ubyte[] p, size_t size, size_t nmemb, OVMEM* pom) nothrow @safe {
	if (!pom) {
		return -1;
	}
	if (pom.pos >= pom.size) {
		return 0;
	}
	if (pom.pos == -1) {
		return 0;
	}

	int left = pom.size - pom.pos;

	if (cast(int)(size * nmemb) >= left) {
		p[0 .. pom.size - pom.pos] = pom.pBuf[pom.pos .. pom.size];
		pom.pos = pom.size;
		return left / size;
	}

	p[] = pom.pBuf[pom.pos .. pom.pos + nmemb * size];
	pom.pos += cast(int)(nmemb * size);

	return nmemb;
}

///
private extern (C) int vorbisSeekCallback(void* pom, long offset, int mode) nothrow @trusted {
	return vorbisSeekCallback(cast(OVMEM*)pom, offset, mode);
}

///
private int vorbisSeekCallback(OVMEM* pom, long offset, int mode) nothrow @safe {
	int newpos;

	if (!pom || pom.pos < 0) {
		return -1;
	}
	if (offset < 0) {
		pom.pos = -1;
		return -1;
	}

	switch (mode) {
	case SEEK_SET:
		newpos = cast(int) offset;
		break;
	case SEEK_CUR:
		newpos = pom.pos + cast(int) offset;
		break;
	case SEEK_END:
		newpos = pom.size + cast(int) offset;
		break;
	default:
		return -1;
	}
	if (newpos < 0) {
		return -1;
	}

	pom.pos = newpos;

	return 0;
}

///
private extern (C) c_long vorbisTellCallback(void* user) nothrow @trusted {
	return vorbisTellCallback(cast(OVMEM*)user);
}

///
private c_long vorbisTellCallback(OVMEM* pom) nothrow @safe {
	if (!pom) {
		return -1;
	}
	return pom.pos;
}

///
private extern (C) int vorbisCloseCallback(void* user) nothrow @trusted {
	return vorbisCloseCallback(cast(OVMEM*)user);
}
///
private int vorbisCloseCallback(OVMEM* pom) nothrow @safe {
	if (!pom) {
		return -1;
	}
	return 0;
}

/////////////////
// global
/////////////////

///
struct PxtnPulseOggv {
private:
	int ch; ///
	int sps2; ///
	int smpNum; ///
	int size; ///
	ubyte[] pData; ///

	///
	private bool setInformation() @safe {
		bool bRet = false;

		OVMEM ovmem;
		ovmem.pBuf = pData;
		ovmem.pos = 0;
		ovmem.size = size;

		// set callback func.
		ov_callbacks oc;
		oc.read_func = &vorbisReadCallback;
		oc.seek_func = &vorbisSeekCallback;
		oc.close_func = &vorbisCloseCallback;
		oc.tell_func = &vorbisTellCallback;

		OggVorbis_File vf;

		vorbis_info* vi;

		trustedOvOpenCallbacks(ovmem, vf, null, oc);

		vi = trustedOvInfo(vf, -1);

		ch = vi.channels;
		sps2 = vi.rate;
		smpNum = cast(int) trustedOvPCMTotal(vf, -1);

		// end.
		trustedOvClear(vf);

		bRet = true;

	End:
		return bRet;

	}

public:
	///
	 ~this() nothrow @safe {
		release();
	}

	///
	void decode(out PxtnPulsePCM pPCM) const @safe {
		OggVorbis_File vf;
		vorbis_info* vi;
		ov_callbacks oc;

		OVMEM ovmem;
		int currentSection;
		byte[4096] pcmout = 0; //take 4k out of the data segment, not the stack

		ovmem.pBuf = pData;
		ovmem.pos = 0;
		ovmem.size = size;

		// set callback func.
		oc.read_func = &vorbisReadCallback;
		oc.seek_func = &vorbisSeekCallback;
		oc.close_func = &vorbisCloseCallback;
		oc.tell_func = &vorbisTellCallback;

		trustedOvOpenCallbacks(ovmem, vf, null, oc);

		vi = trustedOvInfo(vf, -1);

		{
			int tmpSmpNum = cast(int) trustedOvPCMTotal(vf, -1);
			uint bytes;

			bytes = vi.channels * 2 * tmpSmpNum;

			pPCM.create(vi.channels, vi.rate, 16, tmpSmpNum);
		}
		// decode..
		{
			int ret = 0;
			ubyte[] p = pPCM.getPCMBuffer();
			do {
				ret = cast(int)trustedOvRead(vf, pcmout[], 0, 2, 1, currentSection);
				if (ret > 0) {
					p[0 .. ret] = cast(ubyte[])(pcmout[0 .. ret]);
				}
				p = p[ret .. $];
			}
			while (ret);
		}

		// end.
		trustedOvClear(vf);
	}

	///
	void release() nothrow @safe {
		pData = null;
		ch = 0;
		sps2 = 0;
		smpNum = 0;
		size = 0;
	}

	///
	bool getInfo(int* pCh, int* pSPS, int* pSmpNum) nothrow @safe {
		if (!pData) {
			return false;
		}

		if (pCh) {
			*pCh = ch;
		}
		if (pSPS) {
			*pSPS = sps2;
		}
		if (pSmpNum) {
			*pSmpNum = smpNum;
		}

		return true;
	}

	///
	int getSize() const nothrow @safe {
		if (!pData) {
			return 0;
		}
		return cast(int)(int.sizeof * 4 + size);
	}

	///
	void oggWrite(ref PxtnDescriptor desc) const @safe {
		desc.write(pData);
	}

	///
	void oggRead(ref PxtnDescriptor desc) @safe {
		size = desc.getByteSize();
		if (!(size)) {
			throw new PxtoneException("desc r");
		}
		pData = new ubyte[](size);
		scope(failure) {
			pData = null;
			size = 0;
		}
		desc.read(pData);
		if (!setInformation()) {
			throw new PxtoneException("setInformation");
		}
	}

	///
	void pxtnWrite(ref PxtnDescriptor pDoc) const @safe {
		if (!pData) {
			throw new PxtoneException("No data");
		}

		pDoc.write(ch);
		pDoc.write(sps2);
		pDoc.write(smpNum);
		pDoc.write(size);
		pDoc.write(pData);
	}

	///
	void pxtnRead(ref PxtnDescriptor pDoc) @safe {
		pDoc.read(ch);
		pDoc.read(sps2);
		pDoc.read(smpNum);
		pDoc.read(size);

		if (!size) {
			throw new PxtoneException("Invalid size read");
		}

		pData = new ubyte[](size);
		scope(failure) {
			pData = null;
			size = 0;
		}
		pDoc.read(pData);
	}

	///
	bool copy(ref PxtnPulseOggv pDst) const nothrow @safe {
		pDst.release();
		if (!pData) {
			return true;
		}

		pDst.pData = new ubyte[](size);
		if (!(pDst.pData)) {
			return false;
		}
		pDst.pData[0 .. size] = pData[0 .. size];

		pDst.ch = ch;
		pDst.sps2 = sps2;
		pDst.size = size;
		pDst.smpNum = smpNum;

		return true;
	}
}

///
private void trustedOvOpenCallbacks(T)(scope ref T datasource, scope ref OggVorbis_File vf, scope ubyte[] initial, ov_callbacks callbacks) @trusted {
	switch(ov_open_callbacks(cast(void*)&datasource, &vf, cast(char*)initial.ptr, cast(int)initial.length, callbacks)) {
		case 0: break;
		case OV_EREAD:
			throw new PxtoneException("A read from media returned an error");
		case OV_ENOTVORBIS:
			throw new PxtoneException("Bitstream is not Vorbis data");
		case OV_EVERSION:
			throw new PxtoneException("Vorbis version mismatch");
		case OV_EBADHEADER:
			throw new PxtoneException("Invalid Vorbis bitstream header");
		case OV_EFAULT:
			throw new PxtoneException("Internal logic fault; indicates a bug or heap/stack corruption");
		default:
			throw new PxtoneException("Unknown error");
	}
}

///
private c_long trustedOvRead(scope ref OggVorbis_File vf, scope byte[] buffer, bool bigEndianPacking, int wordSize, bool signed, ref int bitstream) @trusted {
	auto result = ov_read(&vf, buffer.ptr, cast(int)buffer.length, bigEndianPacking, wordSize, signed, &bitstream);
	enforce!PxtoneException(result != OV_HOLE, "Vorbis data interrupted");
	enforce!PxtoneException(result != OV_EBADLINK, "Invalid Vorbis stream section or requested link corrupt");
	enforce!PxtoneException(result != OV_EINVAL, "Initial Vorbis headers could not be read or are corrupt");
	enforce!PxtoneException(result >= 0, "Unknown Vorbis error");
	return result;
}

///
private vorbis_info* trustedOvInfo(scope ref OggVorbis_File vf, int link) @trusted {
	auto result = ov_info(&vf, link);
	enforce(result !is null);
	return result;
}

///
private long trustedOvPCMTotal(scope ref OggVorbis_File vf, int link) @trusted {
	auto result = ov_pcm_total(&vf, link);
	enforce(result != OV_EINVAL);
	return result;
}

///
private void trustedOvClear(scope ref OggVorbis_File vf) @trusted {
	enforce(ov_clear(&vf) == 0);
}
