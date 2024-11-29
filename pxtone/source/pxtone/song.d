module pxtone.song;

import pxtone.descriptor;
import pxtone.delay;
import pxtone.evelist;
import pxtone.error;
import pxtone.master;
import pxtone.max;
import pxtone.overdrive;
import pxtone.service;
import pxtone.text;
import pxtone.woice;
import pxtone.unit;

import std.exception;
import std.format;
import std.stdio;

struct PxToneSong {
	pxtnText text;
	pxtnMaster master;
	pxtnEvelist evels;


	_DELAYSTRUCT[] _delays;
	pxtnOverDrive*[] _ovdrvs;
	pxtnWoice*[] _woices;
	pxtnUnit[] _units;

	this(ubyte[] buffer) @safe {
		pxtnDescriptor desc;
		desc.set_memory_r(buffer);
		read(desc);
	}

	this(File fd) @safe {
		pxtnDescriptor desc;
		desc.set_file_r(fd);
		read(desc);
	}
	static bool detect(ubyte[] buffer) @safe {
		PxToneSong tmpSong;
		pxtnDescriptor desc;
		desc.set_memory_r(buffer);
		_enum_FMTVER fmt_ver;
		ushort exe_ver;
		try {
			tmpSong._ReadVersion(desc, fmt_ver, exe_ver);
		} catch(Exception) {
			return false;
		}
		return true;
	}
	void clear() nothrow @safe {
		text.set_name_buf("");
		text.set_comment_buf("");

		evels.Clear();

		_delays = _delays.init;
		_ovdrvs = _ovdrvs.init;
		_woices = _woices.init;
		_units = _units.init;

		master.Reset();

		evels.Release();
	}
	void read(ref pxtnDescriptor p_doc) @safe {
		ushort exe_ver = 0;
		_enum_FMTVER fmt_ver = _enum_FMTVER._enum_FMTVER_unknown;
		int event_num = 0;

		clear();

		scope(failure) {
			clear();
		}

		_pre_count_event(p_doc, event_num);
		p_doc.seek(pxtnSEEK.set, 0);

		evels.Allocate(event_num);

		_ReadVersion(p_doc, fmt_ver, exe_ver);

		if (fmt_ver >= _enum_FMTVER._enum_FMTVER_v5) {
			evels.Linear_Start();
		} else {
			evels.x4x_Read_Start();
		}

		_ReadTuneItems(p_doc);

		if (fmt_ver >= _enum_FMTVER._enum_FMTVER_v5) {
			evels.Linear_End(true);
		}

		if (fmt_ver <= _enum_FMTVER._enum_FMTVER_x3x) {
			if (!_x3x_TuningKeyEvent()) {
				throw new PxtoneException("x3x key");
			}
			if (!_x3x_AddTuningEvent()) {
				throw new PxtoneException("x3x add tuning");
			}
			_x3x_SetVoiceNames();
		}

		{
			int clock1 = evels.get_Max_Clock();
			int clock2 = master.get_last_clock();

			if (clock1 > clock2) {
				master.AdjustMeasNum(clock1);
			} else {
				master.AdjustMeasNum(clock2);
			}
		}
	}
	////////////////////////////////////////
	// save               //////////////////
	////////////////////////////////////////

	void write(ref pxtnDescriptor p_doc, bool b_tune, ushort exe_ver) @safe {
		bool b_ret = false;
		int rough = b_tune ? 10 : 1;
		ushort rrr = 0;

		// format version
		if (b_tune) {
			p_doc.w_asfile(_code_tune_v5);
		} else {
			p_doc.w_asfile(_code_proj_v5);
		}

		// exe version
		p_doc.w_asfile(exe_ver);
		p_doc.w_asfile(rrr);

		// master
		p_doc.w_asfile(_code_MasterV5);
		master.io_w_v5(p_doc, rough);

		// event
		p_doc.w_asfile(_code_Event_V5);
		evels.io_Write(p_doc, rough);

		// name
		if (text.is_name_buf()) {
			p_doc.w_asfile(_code_textNAME);
			_write4_tag(text.get_name_buf(), p_doc);
		}

		// comment
		if (text.is_comment_buf()) {
			p_doc.w_asfile(_code_textCOMM);
			_write4_tag(text.get_comment_buf(), p_doc);
		}

		// delay
		for (int d = 0; d < _delays.length; d++) {
			p_doc.w_asfile(_code_effeDELA);

			_DELAYSTRUCT dela;
			int size;

			dela.unit = cast(ushort) _delays[d].unit;
			dela.group = cast(ushort) _delays[d].group;
			dela.rate = _delays[d].rate;
			dela.freq = _delays[d].freq;

			// dela ----------
			size = _DELAYSTRUCT.sizeof;
			p_doc.w_asfile(size);
			p_doc.w_asfile(dela);
		}

		// overdrive
		for (int o = 0; o < _ovdrvs.length; o++) {
			p_doc.w_asfile(_code_effeOVER);
			_ovdrvs[o].Write(p_doc);
		}

		// woice
		for (int w = 0; w < _woices.length; w++) {
			pxtnWoice* p_w = _woices[w];

			switch (p_w.get_type()) {
			case pxtnWOICETYPE.PCM:
				p_doc.w_asfile(_code_matePCM);
				p_w.io_matePCM_w(p_doc);
				break;
			case pxtnWOICETYPE.PTV:
				p_doc.w_asfile(_code_matePTV);
				if (!p_w.io_matePTV_w(p_doc)) {
					throw new PxtoneException("desc w");
				}
				break;
			case pxtnWOICETYPE.PTN:
				p_doc.w_asfile(_code_matePTN);
				p_w.io_matePTN_w(p_doc);
				break;
			case pxtnWOICETYPE.OGGV:

				version (pxINCLUDE_OGGVORBIS) {
					p_doc.w_asfile(_code_mateOGGV);
					if (!p_w.io_mateOGGV_w(p_doc)) {
						throw new PxtoneException("desc w");
					}
					break;
				} else {
					throw new PxtoneException("Ogg vorbis support is required");
				}
			default:
				throw new PxtoneException("inv data");
			}

			if (!b_tune && p_w.is_name_buf()) {
				p_doc.w_asfile(_code_assiWOIC);
				if (!_io_assiWOIC_w(p_doc, w)) {
					throw new PxtoneException("desc w");
				}
			}
		}

		// unit
		p_doc.w_asfile(_code_num_UNIT);
		_io_UNIT_num_w(p_doc);

		for (int u = 0; u < _units.length; u++) {
			if (!b_tune && _units[u].is_name_buf()) {
				p_doc.w_asfile(_code_assiUNIT);
				if (!_io_assiUNIT_w(p_doc, u)) {
					throw new PxtoneException("desc w");
				}
			}
		}

		{
			int end_size = 0;
			p_doc.w_asfile(_code_pxtoneND);
			p_doc.w_asfile(end_size);
		}
	}
	////////////////////////////////////////
	// Read Project //////////////
	////////////////////////////////////////

	void _ReadTuneItems(ref pxtnDescriptor p_doc) @safe {
		bool b_end = false;
		char[_CODESIZE + 1] code = '\0';

		/// must the unit before the voice.
		while (!b_end) {
			p_doc.r(code[0 .._CODESIZE]);

			_enum_Tag tag = _CheckTagCode(code);
			switch (tag) {
			case _enum_Tag.antiOPER:
				throw new PxtoneException("AntiOPER tag detected");

				// new -------
			case _enum_Tag.num_UNIT: {
					int num = 0;
					_io_UNIT_num_r(p_doc, num);
					_units.length = num;
					break;
				}
			case _enum_Tag.MasterV5:
				master.io_r_v5(p_doc);
				break;
			case _enum_Tag.Event_V5:
				evels.io_Read(p_doc);
				break;

			case _enum_Tag.matePCM:
				_io_Read_Woice(p_doc, pxtnWOICETYPE.PCM);
				break;
			case _enum_Tag.matePTV:
				_io_Read_Woice(p_doc, pxtnWOICETYPE.PTV);
				break;
			case _enum_Tag.matePTN:
				_io_Read_Woice(p_doc, pxtnWOICETYPE.PTN);
				break;

			case _enum_Tag.mateOGGV:

				version (pxINCLUDE_OGGVORBIS) {
					_io_Read_Woice(p_doc, pxtnWOICETYPE.OGGV);
					break;
				} else {
					throw new PxtoneException("Ogg Vorbis support is required");
				}

			case _enum_Tag.effeDELA:
				_io_Read_Delay(p_doc);
				break;
			case _enum_Tag.effeOVER:
				_io_Read_OverDrive(p_doc);
				break;
			case _enum_Tag.textNAME:
				text.set_name_buf(_read4_tag(p_doc));
				break;
			case _enum_Tag.textCOMM:
				text.set_comment_buf(_read4_tag(p_doc));
				break;
			case _enum_Tag.assiWOIC:
				_io_assiWOIC_r(p_doc);
				break;
			case _enum_Tag.assiUNIT:
				_io_assiUNIT_r(p_doc);
				break;
			case _enum_Tag.pxtoneND:
				b_end = true;
				break;

				// old -------
			case _enum_Tag.x4x_evenMAST:
				master.io_r_x4x(p_doc);
				break;
			case _enum_Tag.x4x_evenUNIT:
				evels.io_Unit_Read_x4x_EVENT(p_doc, false, true);
				break;
			case _enum_Tag.x3x_pxtnUNIT:
				_io_Read_OldUnit(p_doc, 3);
				break;
			case _enum_Tag.x1x_PROJ:
				_x1x_Project_Read(p_doc);
				break;
			case _enum_Tag.x1x_UNIT:
				_io_Read_OldUnit(p_doc, 1);
				break;
			case _enum_Tag.x1x_PCM:
				_io_Read_Woice(p_doc, pxtnWOICETYPE.PCM);
				break;
			case _enum_Tag.x1x_EVEN:
				evels.io_Unit_Read_x4x_EVENT(p_doc, true, false);
				break;
			case _enum_Tag.x1x_END:
				b_end = true;
				break;

			default:
				throw new PxtoneException("fmt unknown");
			}
		}

	}
	void _ReadVersion(ref pxtnDescriptor p_doc, out _enum_FMTVER p_fmt_ver, out ushort p_exe_ver) @safe {
		char[_VERSIONSIZE] version_ = '\0';
		ushort dummy;

		p_doc.r(version_[]);

		// fmt version
		if (version_[0 .. _VERSIONSIZE] == _code_proj_x1x) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_x1x;
			p_exe_ver = 0;
			return;
		} else if (version_[0 .. _VERSIONSIZE] == _code_proj_x2x) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_x2x;
			p_exe_ver = 0;
			return;
		} else if (version_[0 .. _VERSIONSIZE] == _code_proj_x3x) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_x3x;
		} else if (version_[0 .. _VERSIONSIZE] == _code_proj_x4x) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_x4x;
		} else if (version_[0 .. _VERSIONSIZE] == _code_proj_v5) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_v5;
		} else if (version_[0 .. _VERSIONSIZE] == _code_tune_x2x) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_x2x;
			p_exe_ver = 0;
			return;
		} else if (version_[0 .. _VERSIONSIZE] == _code_tune_x3x) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_x3x;
		} else if (version_[0 .. _VERSIONSIZE] == _code_tune_x4x) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_x4x;
		} else if (version_[0 .. _VERSIONSIZE] == _code_tune_v5) {
			p_fmt_ver = _enum_FMTVER._enum_FMTVER_v5;
		} else {
			throw new PxtoneException("fmt unknown");
		}

		// exe version
		p_doc.r(p_exe_ver);
		p_doc.r(dummy);
	}

	void _x1x_Project_Read(ref pxtnDescriptor p_doc) @safe {
		_x1x_PROJECT prjc;
		int beat_num, beat_clock;
		int size;
		float beat_tempo;

		p_doc.r(size);
		p_doc.r(prjc);

		beat_num = prjc.x1x_beat_num;
		beat_tempo = prjc.x1x_beat_tempo;
		beat_clock = prjc.x1x_beat_clock;

		int ns = 0;
		for ( /+ns+/ ; ns < _MAX_PROJECTNAME_x1x; ns++) {
			if (!prjc.x1x_name[ns]) {
				break;
			}
		}

		text.set_name_buf(prjc.x1x_name[0 .. ns].dup);
		master.Set(beat_num, beat_tempo, beat_clock);
	}

	void _io_Read_Delay(ref pxtnDescriptor p_doc) @safe {
		if (pxtnMAX_TUNEDELAYSTRUCT < _delays.length) {
			throw new PxtoneException("fmt unknown");
		}

		_DELAYSTRUCT delay;
		int size = 0;

		p_doc.r(size);
		p_doc.r(delay);
		if (delay.unit >= DELAYUNIT.num) {
			throw new PxtoneException("fmt unknown");
		}

		if (delay.group >= pxtnMAX_TUNEGROUPNUM) {
			delay.group = 0;
		}

		_delays ~= delay;
	}

	void _io_Read_OverDrive(ref pxtnDescriptor p_doc) @safe {
		if (pxtnMAX_TUNEOVERDRIVESTRUCT < _ovdrvs.length) {
			throw new PxtoneException("fmt unknown");
		}

		pxtnOverDrive* ovdrv = new pxtnOverDrive();
		ovdrv.Read(p_doc);
		_ovdrvs ~= ovdrv;
	}

	void _io_Read_Woice(ref pxtnDescriptor p_doc, pxtnWOICETYPE type) @safe {
		if (pxtnMAX_TUNEWOICESTRUCT < _woices.length) {
			throw new PxtoneException("Too many woices");
		}

		pxtnWoice* woice = new pxtnWoice();

		switch (type) {
		case pxtnWOICETYPE.PCM:
			woice.io_matePCM_r(p_doc);
			break;
		case pxtnWOICETYPE.PTV:
			woice.io_matePTV_r(p_doc);
			break;
		case pxtnWOICETYPE.PTN:
			woice.io_matePTN_r(p_doc);
			break;
		case pxtnWOICETYPE.OGGV:
			version (pxINCLUDE_OGGVORBIS) {
				woice.io_mateOGGV_r(p_doc);
				break;
			} else {
				throw new PxtoneException("Ogg Vorbis support is required");
			}

		default:
			throw new PxtoneException("fmt unknown");
		}
		_woices ~= woice;
	}

	void _io_Read_OldUnit(ref pxtnDescriptor p_doc, int ver) @safe {
		if (pxtnMAX_TUNEUNITSTRUCT < _units.length) {
			throw new PxtoneException("fmt unknown");
		}

		pxtnUnit* unit = new pxtnUnit();
		int group = 0;
		switch (ver) {
		case 1:
			unit.Read_v1x(p_doc, group);
			break;
		case 3:
			unit.Read_v3x(p_doc, group);
			break;
		default:
			throw new PxtoneException("fmt unknown");
		}

		if (group >= pxtnMAX_TUNEGROUPNUM) {
			group = pxtnMAX_TUNEGROUPNUM - 1;
		}

		evels.x4x_Read_Add(0, cast(ubyte) _units.length, EVENTKIND.GROUPNO, cast(int) group);
		evels.x4x_Read_NewKind();
		evels.x4x_Read_Add(0, cast(ubyte) _units.length, EVENTKIND.VOICENO, cast(int) _units.length);
		evels.x4x_Read_NewKind();

		_units ~= *unit;
	}

	/////////////
	// comments
	/////////////

	const(char)[] _read4_tag(ref pxtnDescriptor p_doc) @safe {
		char[] result;
		int p_buf_size;
		p_doc.r(p_buf_size);
		enforce(p_buf_size >= 0, "Invalid string size");

		if (p_buf_size) {
			result = new char[](p_buf_size);
			p_doc.r(result[0 .. p_buf_size]);
		}
		return result;
	}
	private void _write4_tag(const char[] p, ref pxtnDescriptor p_doc) @safe {
		p_doc.w_asfile(cast(int)p.length);
		p_doc.w_asfile(p);
	}

	/////////////
	// assi woice
	/////////////

	bool _io_assiWOIC_w(ref pxtnDescriptor p_doc, int idx) const @safe {
		_ASSIST_WOICE assi;
		int size;
		const char[] p_name = _woices[idx].get_name_buf();

		if (p_name.length > pxtnMAX_TUNEWOICENAME) {
			return false;
		}

		assi.name[0 .. p_name.length] = p_name;
		assi.woice_index = cast(ushort) idx;

		size = _ASSIST_WOICE.sizeof;
		p_doc.w_asfile(size);
		p_doc.w_asfile(assi);

		return true;
	}

	void _io_assiWOIC_r(ref pxtnDescriptor p_doc) @safe {
		_ASSIST_WOICE assi;
		int size = 0;

		p_doc.r(size);
		if (size != assi.sizeof) {
			throw new PxtoneException("fmt unknown");
		}
		p_doc.r(assi);
		if (assi.rrr) {
			throw new PxtoneException("fmt unknown");
		}
		if (assi.woice_index >= _woices.length) {
			throw new PxtoneException("fmt unknown");
		}

		if (!_woices[assi.woice_index].set_name_buf(assi.name.dup)) {
			throw new PxtoneException("FATAL");
		}
	}
	// -----
	// assi unit.
	// -----

	bool _io_assiUNIT_w(ref pxtnDescriptor p_doc, int idx) const @safe {
		_ASSIST_UNIT assi;
		int size;
		const(char)[] p_name = _units[idx].get_name_buf();

		assi.name[0 .. p_name.length] = p_name[];
		assi.unit_index = cast(ushort) idx;

		size = assi.sizeof;
		p_doc.w_asfile(size);
		p_doc.w_asfile(assi);

		return true;
	}

	void _io_assiUNIT_r(ref pxtnDescriptor p_doc) @safe {
		_ASSIST_UNIT assi;
		int size;

		p_doc.r(size);
		if (size != assi.sizeof) {
			throw new PxtoneException("fmt unknown");
		}
		p_doc.r(assi);
		if (assi.rrr) {
			throw new PxtoneException("fmt unknown");
		}
		if (assi.unit_index >= _units.length) {
			throw new PxtoneException("fmt unknown");
		}

		if (!_units[assi.unit_index].setNameBuf(assi.name[])) {
			throw new PxtoneException("FATAL");
		}
	}
	// -----
	// unit num
	// -----

	void _io_UNIT_num_w(ref pxtnDescriptor p_doc) const @safe {
		_NUM_UNIT data;
		int size;

		data.num = cast(short) _units.length;

		size = _NUM_UNIT.sizeof;
		p_doc.w_asfile(size);
		p_doc.w_asfile(data);
	}

	void _io_UNIT_num_r(ref pxtnDescriptor p_doc, out int p_num) @safe {
		_NUM_UNIT data;
		int size = 0;

		p_doc.r(size);
		if (size != _NUM_UNIT.sizeof) {
			throw new PxtoneException("fmt unknown");
		}
		p_doc.r(data);
		if (data.rrr) {
			throw new PxtoneException("fmt unknown");
		}
		if (data.num > pxtnMAX_TUNEUNITSTRUCT) {
			throw new PxtoneException("fmt new");
		}
		if (data.num < 0) {
			throw new PxtoneException("fmt unknown");
		}
		p_num = data.num;
	}

	// fix old key event
	bool _x3x_TuningKeyEvent() nothrow @safe {
		if (_units.length > _woices.length) {
			return false;
		}

		for (int u = 0; u < _units.length; u++) {
			if (u >= _woices.length) {
				return false;
			}

			int change_value = _woices[u].get_x3x_basic_key() - EVENTDEFAULT_BASICKEY;

			if (!evels.get_Count(cast(ubyte) u, cast(ubyte) EVENTKIND.KEY)) {
				evels.Record_Add_i(0, cast(ubyte) u, EVENTKIND.KEY, cast(int) 0x6000);
			}
			evels.Record_Value_Change(0, -1, cast(ubyte) u, EVENTKIND.KEY, change_value);
		}
		return true;
	}

	// fix old tuning (1.0)
	bool _x3x_AddTuningEvent() nothrow @safe {
		if (_units.length > _woices.length) {
			return false;
		}

		for (int u = 0; u < _units.length; u++) {
			float tuning = _woices[u].get_x3x_tuning();
			if (tuning) {
				evels.Record_Add_f(0, cast(ubyte) u, EVENTKIND.TUNING, tuning);
			}
		}

		return true;
	}

	bool _x3x_SetVoiceNames() nothrow @safe {
		for (int i = 0; i < _woices.length; i++) {
			char[pxtnMAX_TUNEWOICENAME + 1] name = 0;
			try {
				sformat(name[], "voice_%02d", i);
			} catch (Exception) { //This will never actually happen...
				return false;
			}
			_woices[i].set_name_buf(name.dup);
		}
		return true;
	}
	void _pre_count_event(ref pxtnDescriptor p_doc, out int p_count) @safe {
		bool b_end = false;

		int count = 0;
		int c = 0;
		int size = 0;
		char[_CODESIZE + 1] code = '\0';

		ushort exe_ver = 0;
		_enum_FMTVER fmt_ver = _enum_FMTVER._enum_FMTVER_unknown;

		scope(failure) {
			p_count = 0;
		}

		_ReadVersion(p_doc, fmt_ver, exe_ver);

		if (fmt_ver == _enum_FMTVER._enum_FMTVER_x1x) {
			count = _MAX_FMTVER_x1x_EVENTNUM;
			goto term;
		}

		while (!b_end) {
			p_doc.r(code[0 .. _CODESIZE]);

			switch (_CheckTagCode(code)) {
			case _enum_Tag.Event_V5:
				count += evels.io_Read_EventNum(p_doc);
				break;
			case _enum_Tag.MasterV5:
				count += master.io_r_v5_EventNum(p_doc);
				break;
			case _enum_Tag.x4x_evenMAST:
				count += master.io_r_x4x_EventNum(p_doc);
				break;
			case _enum_Tag.x4x_evenUNIT:
				evels.io_Read_x4x_EventNum(p_doc, c);
				count += c;
				break;
			case _enum_Tag.pxtoneND:
				b_end = true;
				break;

				// skip
			case _enum_Tag.antiOPER:
			case _enum_Tag.num_UNIT:
			case _enum_Tag.x3x_pxtnUNIT:
			case _enum_Tag.matePCM:
			case _enum_Tag.matePTV:
			case _enum_Tag.matePTN:
			case _enum_Tag.mateOGGV:
			case _enum_Tag.effeDELA:
			case _enum_Tag.effeOVER:
			case _enum_Tag.textNAME:
			case _enum_Tag.textCOMM:
			case _enum_Tag.assiUNIT:
			case _enum_Tag.assiWOIC:

				p_doc.r(size);
				p_doc.seek(pxtnSEEK.cur, size);
				break;

				// ignore
			case _enum_Tag.x1x_PROJ:
			case _enum_Tag.x1x_UNIT:
			case _enum_Tag.x1x_PCM:
			case _enum_Tag.x1x_EVEN:
			case _enum_Tag.x1x_END:
				throw new PxtoneException("x1x ignore");
			default:
				throw new PxtoneException("FATAL");
			}
		}

		if (fmt_ver <= _enum_FMTVER._enum_FMTVER_x3x) {
			count += pxtnMAX_TUNEUNITSTRUCT * 4; // voice_no, group_no, key tuning, key event x3x
		}

	term:

		p_count = count;
	}
}


private _enum_Tag _CheckTagCode(scope const char[] p_code) nothrow @safe {
	switch(p_code[0 .. _CODESIZE]) {
		case _code_antiOPER: return _enum_Tag.antiOPER;
		case _code_x1x_PROJ: return _enum_Tag.x1x_PROJ;
		case _code_x1x_UNIT: return _enum_Tag.x1x_UNIT;
		case _code_x1x_PCM: return _enum_Tag.x1x_PCM;
		case _code_x1x_EVEN: return _enum_Tag.x1x_EVEN;
		case _code_x1x_END: return _enum_Tag.x1x_END;
		case _code_x3x_pxtnUNIT: return _enum_Tag.x3x_pxtnUNIT;
		case _code_x4x_evenMAST: return _enum_Tag.x4x_evenMAST;
		case _code_x4x_evenUNIT: return _enum_Tag.x4x_evenUNIT;
		case _code_num_UNIT: return _enum_Tag.num_UNIT;
		case _code_Event_V5: return _enum_Tag.Event_V5;
		case _code_MasterV5: return _enum_Tag.MasterV5;
		case _code_matePCM: return _enum_Tag.matePCM;
		case _code_matePTV: return _enum_Tag.matePTV;
		case _code_matePTN: return _enum_Tag.matePTN;
		case _code_mateOGGV: return _enum_Tag.mateOGGV;
		case _code_effeDELA: return _enum_Tag.effeDELA;
		case _code_effeOVER: return _enum_Tag.effeOVER;
		case _code_textNAME: return _enum_Tag.textNAME;
		case _code_textCOMM: return _enum_Tag.textCOMM;
		case _code_assiUNIT: return _enum_Tag.assiUNIT;
		case _code_assiWOIC: return _enum_Tag.assiWOIC;
		case _code_pxtoneND: return _enum_Tag.pxtoneND;
		default: return _enum_Tag.Unknown;
	}
}
