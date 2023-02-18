module pxtone.pulse.oggv;

version (pxINCLUDE_OGGVORBIS):
import core.stdc.config;
import derelict.vorbis.codec;
import derelict.vorbis.file;

import pxtone.descriptor;
import pxtone.error;
import pxtone.pulse.pcm;

import std.exception;
import std.stdio;

struct OVMEM {
	const(ubyte)[] p_buf; // ogg vorbis-data on memory.s
	int size; //
	int pos; // reading position.
}

// 4 callbacks below:

private extern (C) size_t _mread(void* p, size_t size, size_t nmemb, void* p_void) nothrow @trusted {
	return _mread((cast(ubyte*)p)[0 .. size * nmemb], size, nmemb, cast(OVMEM*)p_void);
}
private size_t _mread(ubyte[] p, size_t size, size_t nmemb, OVMEM* pom) nothrow @safe {
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
		p[0 .. pom.size - pom.pos] = pom.p_buf[pom.pos .. pom.size];
		pom.pos = pom.size;
		return left / size;
	}

	p[] = pom.p_buf[pom.pos .. pom.pos + nmemb * size];
	pom.pos += cast(int)(nmemb * size);

	return nmemb;
}

private extern (C) int _mseek(void* pom, long offset, int mode) nothrow @trusted {
	return _mseek(cast(OVMEM*)pom, offset, mode);
}
private int _mseek(OVMEM* pom, long offset, int mode) nothrow @safe {
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

private extern (C) c_long _mtell(void* p_void) nothrow @trusted {
	return _mtell(cast(OVMEM*)p_void);
}
private c_long _mtell(OVMEM* pom) nothrow @safe {
	if (!pom) {
		return -1;
	}
	return pom.pos;
}

private extern (C) int _mclose_dummy(void* p_void) nothrow @trusted {
	return _mclose_dummy(cast(OVMEM*)p_void);
}
private int _mclose_dummy(OVMEM* pom) nothrow @safe {
	if (!pom) {
		return -1;
	}
	return 0;
}

/////////////////
// global
/////////////////

struct pxtnPulse_Oggv {
private:
	int _ch;
	int _sps2;
	int _smp_num;
	int _size;
	ubyte[] _p_data;

	bool _SetInformation() @safe {
		bool b_ret = false;

		OVMEM ovmem;
		ovmem.p_buf = _p_data;
		ovmem.pos = 0;
		ovmem.size = _size;

		// set callback func.
		ov_callbacks oc;
		oc.read_func = &_mread;
		oc.seek_func = &_mseek;
		oc.close_func = &_mclose_dummy;
		oc.tell_func = &_mtell;

		OggVorbis_File vf;

		vorbis_info* vi;

		trustedOvOpenCallbacks(ovmem, vf, null, oc);

		vi = trustedOvInfo(vf, -1);

		_ch = vi.channels;
		_sps2 = vi.rate;
		_smp_num = cast(int) trustedOvPCMTotal(vf, -1);

		// end.
		trustedOvClear(vf);

		b_ret = true;

	End:
		return b_ret;

	}

public:
	 ~this() nothrow @safe {
		Release();
	}

	void Decode(pxtnPulse_PCM* p_pcm) const @safe {
		OggVorbis_File vf;
		vorbis_info* vi;
		ov_callbacks oc;

		OVMEM ovmem;
		int current_section;
		byte[4096] pcmout = 0; //take 4k out of the data segment, not the stack

		ovmem.p_buf = _p_data;
		ovmem.pos = 0;
		ovmem.size = _size;

		// set callback func.
		oc.read_func = &_mread;
		oc.seek_func = &_mseek;
		oc.close_func = &_mclose_dummy;
		oc.tell_func = &_mtell;

		trustedOvOpenCallbacks(ovmem, vf, null, oc);

		vi = trustedOvInfo(vf, -1);

		{
			int smp_num = cast(int) trustedOvPCMTotal(vf, -1);
			uint bytes;

			bytes = vi.channels * 2 * smp_num;

			p_pcm.Create(vi.channels, vi.rate, 16, smp_num);
		}
		// decode..
		{
			int ret = 0;
			ubyte[] p = p_pcm.get_p_buf();
			do {
				ret = cast(int)trustedOvRead(vf, pcmout[], 0, 2, 1, current_section);
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

	void Release() nothrow @safe {
		_p_data = null;
		_ch = 0;
		_sps2 = 0;
		_smp_num = 0;
		_size = 0;
	}

	bool GetInfo(int* p_ch, int* p_sps, int* p_smp_num) nothrow @safe {
		if (!_p_data) {
			return false;
		}

		if (p_ch) {
			*p_ch = _ch;
		}
		if (p_sps) {
			*p_sps = _sps2;
		}
		if (p_smp_num) {
			*p_smp_num = _smp_num;
		}

		return true;
	}

	int GetSize() const nothrow @safe {
		if (!_p_data) {
			return 0;
		}
		return cast(int)(int.sizeof * 4 + _size);
	}

	void ogg_write(ref pxtnDescriptor desc) const @safe {
		desc.w_asfile(_p_data);
	}

	void ogg_read(ref pxtnDescriptor desc) @safe {
		_size = desc.get_size_bytes();
		if (!(_size)) {
			throw new PxtoneException("desc r");
		}
		_p_data = new ubyte[](_size);
		scope(failure) {
			_p_data = null;
			_size = 0;
		}
		desc.r(_p_data);
		if (!_SetInformation()) {
			throw new PxtoneException("_SetInformation");
		}
	}

	void pxtn_write(ref pxtnDescriptor p_doc) const @safe {
		if (!_p_data) {
			throw new PxtoneException("No data");
		}

		p_doc.w_asfile(_ch);
		p_doc.w_asfile(_sps2);
		p_doc.w_asfile(_smp_num);
		p_doc.w_asfile(_size);
		p_doc.w_asfile(_p_data);
	}

	void pxtn_read(ref pxtnDescriptor p_doc) @safe {
		p_doc.r(_ch);
		p_doc.r(_sps2);
		p_doc.r(_smp_num);
		p_doc.r(_size);

		if (!_size) {
			throw new PxtoneException("Invalid size read");
		}

		_p_data = new ubyte[](_size);
		scope(failure) {
			_p_data = null;
			_size = 0;
		}
		p_doc.r(_p_data);
	}

	bool Copy(ref pxtnPulse_Oggv p_dst) const nothrow @safe {
		p_dst.Release();
		if (!_p_data) {
			return true;
		}

		p_dst._p_data = new ubyte[](_size);
		if (!(p_dst._p_data)) {
			return false;
		}
		p_dst._p_data[0 .. _size] = _p_data[0 .. _size];

		p_dst._ch = _ch;
		p_dst._sps2 = _sps2;
		p_dst._size = _size;
		p_dst._smp_num = _smp_num;

		return true;
	}
}

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

private c_long trustedOvRead(scope ref OggVorbis_File vf, scope byte[] buffer, bool bigEndianPacking, int wordSize, bool signed, ref int bitstream) @trusted {
	auto result = ov_read(&vf, buffer.ptr, cast(int)buffer.length, bigEndianPacking, wordSize, signed, &bitstream);
	enforce!PxtoneException(result != OV_HOLE, "Vorbis data interrupted");
	enforce!PxtoneException(result != OV_EBADLINK, "Invalid Vorbis stream section or requested link corrupt");
	enforce!PxtoneException(result != OV_EINVAL, "Initial Vorbis headers could not be read or are corrupt");
	enforce!PxtoneException(result >= 0, "Unknown Vorbis error");
	return result;
}
private vorbis_info* trustedOvInfo(scope ref OggVorbis_File vf, int link) @trusted {
	auto result = ov_info(&vf, link);
	enforce(result !is null);
	return result;
}

private long trustedOvPCMTotal(scope ref OggVorbis_File vf, int link) @trusted {
	auto result = ov_pcm_total(&vf, link);
	enforce(result != OV_EINVAL);
	return result;
}

private void trustedOvClear(scope ref OggVorbis_File vf) @trusted {
	enforce(ov_clear(&vf) == 0);
}
