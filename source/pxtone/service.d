module pxtone.service;

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.pulse.noisebuilder;

import pxtone.error;
import pxtone.max;
import pxtone.text;
import pxtone.delay;
import pxtone.overdrive;
import pxtone.master;
import pxtone.woice;
import pxtone.song;
import pxtone.pulse.frequency;
import pxtone.unit;
import pxtone.evelist;

import std.algorithm.comparison;
import std.exception;
import std.format;
import std.math;
import std.stdio;
import std.typecons;

enum PXTONEERRORSIZE = 64;

enum pxtnFlags {
	loop = 1 << 0,
	unitMute = 1 << 1
}

enum _VERSIONSIZE = 16;
enum _CODESIZE = 8;

//                                       0123456789012345
immutable _code_tune_x2x = "PTTUNE--20050608";
immutable _code_tune_x3x = "PTTUNE--20060115";
immutable _code_tune_x4x = "PTTUNE--20060930";
immutable _code_tune_v5 = "PTTUNE--20071119";

immutable _code_proj_x1x = "PTCOLLAGE-050227";
immutable _code_proj_x2x = "PTCOLLAGE-050608";
immutable _code_proj_x3x = "PTCOLLAGE-060115";
immutable _code_proj_x4x = "PTCOLLAGE-060930";
immutable _code_proj_v5 = "PTCOLLAGE-071119";

immutable _code_x1x_PROJ = "PROJECT=";
immutable _code_x1x_EVEN = "EVENT===";
immutable _code_x1x_UNIT = "UNIT====";
immutable _code_x1x_END = "END=====";
immutable _code_x1x_PCM = "matePCM=";

immutable _code_x3x_pxtnUNIT = "pxtnUNIT";
immutable _code_x4x_evenMAST = "evenMAST";
immutable _code_x4x_evenUNIT = "evenUNIT";

immutable _code_antiOPER = "antiOPER"; // anti operation(edit)

immutable _code_num_UNIT = "num UNIT";
immutable _code_MasterV5 = "MasterV5";
immutable _code_Event_V5 = "Event V5";
immutable _code_matePCM = "matePCM ";
immutable _code_matePTV = "matePTV ";
immutable _code_matePTN = "matePTN ";
immutable _code_mateOGGV = "mateOGGV";
immutable _code_effeDELA = "effeDELA";
immutable _code_effeOVER = "effeOVER";
immutable _code_textNAME = "textNAME";
immutable _code_textCOMM = "textCOMM";
immutable _code_assiUNIT = "assiUNIT";
immutable _code_assiWOIC = "assiWOIC";
immutable _code_pxtoneND = "pxtoneND";

enum _enum_Tag {
	Unknown = 0,
	antiOPER,

	x1x_PROJ,
	x1x_UNIT,
	x1x_PCM,
	x1x_EVEN,
	x1x_END,
	x3x_pxtnUNIT,
	x4x_evenMAST,
	x4x_evenUNIT,

	num_UNIT,
	MasterV5,
	Event_V5,
	matePCM,
	matePTV,
	matePTN,
	mateOGGV,
	effeDELA,
	effeOVER,
	textNAME,
	textCOMM,
	assiUNIT,
	assiWOIC,
	pxtoneND

}


struct _ASSIST_WOICE {
	ushort woice_index;
	ushort rrr;
	char[pxtnMAX_TUNEWOICENAME] name = 0;
}

struct _ASSIST_UNIT {
	ushort unit_index;
	ushort rrr;
	char[pxtnMAX_TUNEUNITNAME] name = 0;
}

struct _NUM_UNIT {
	short num;
	short rrr;
}

enum _MAX_FMTVER_x1x_EVENTNUM = 10000;

// x1x project..------------------

enum _MAX_PROJECTNAME_x1x = 16;

// project (36byte) ================
struct _x1x_PROJECT {
	char[_MAX_PROJECTNAME_x1x] x1x_name = 0;

	float x1x_beat_tempo = 0.0;
	ushort x1x_beat_clock;
	ushort x1x_beat_num;
	ushort x1x_beat_note;
	ushort x1x_meas_num;
	ushort x1x_channel_num;
	ushort x1x_bps;
	uint x1x_sps;
}

struct pxtnVOMITPREPARATION {
	int start_pos_meas = 0;
	int start_pos_sample = 0;
	float start_pos_float = 0.0;

	int meas_end = 0;
	int meas_repeat = 0;
	float fadein_sec = 0.0;

	BitFlags!pxtnFlags flags;
	float master_volume = 1.0;
	invariant {
		import std.math : isNaN;
		assert(!master_volume.isNaN, "Master volume should never be NaN!");
		assert(!fadein_sec.isNaN, "fadein_sec should never be NaN!");
		assert(!start_pos_float.isNaN, "start_pos_float should never be NaN!");
	}
}

alias pxtnSampledCallback = bool function(void* user, const(pxtnService)* pxtn) nothrow;

package enum _enum_FMTVER {
	_enum_FMTVER_unknown = 0,
	_enum_FMTVER_x1x, // fix event num = 10000
	_enum_FMTVER_x2x, // no version of exe
	_enum_FMTVER_x3x, // unit has voice / basic-key for only view
	_enum_FMTVER_x4x, // unit has event
	_enum_FMTVER_v5,
}
struct pxtnService {
private:

	bool _b_init;
	bool _b_edit;
	bool _b_fix_evels_num;

	int _dst_ch_num, _dst_sps, _dst_byte_per_smp;

	pxtnPulse_NoiseBuilder _ptn_bldr;

	pxtnDelay[] _delays;
	pxtnOverDrive*[] _ovdrvs;
	pxtnWoice*[] _woices;
	pxtnUnit[] _units;

	const(PxToneSong)* song;

	//////////////
	// vomit..
	//////////////
	bool _moo_b_valid_data;
	bool _moo_b_end_vomit = true;
	bool _moo_b_init;

	bool _moo_b_mute_by_unit;
	bool _moo_b_loop = true;

	int _moo_smp_smooth;
	float _moo_clock_rate; // as the sample
	int _moo_smp_count;
	int _moo_smp_start;
	int _moo_smp_end;
	int _moo_smp_repeat;

	int _moo_fade_count;
	int _moo_fade_max;
	int _moo_fade_fade;
	float _moo_master_vol = 1.0f;

	int _moo_top;
	float _moo_smp_stride;
	int _moo_time_pan_index;

	float _moo_bt_tempo;

	// for make now-meas
	int _moo_bt_clock;
	int _moo_bt_num;

	int[] _moo_group_smps;

	const(EVERECORD)* _moo_p_eve;

	pxtnPulse_Frequency* _moo_freq;

	void _init(int fix_evels_num, bool b_edit) @system {
		if (_b_init) {
			throw new PxtoneException("pxtnService not initialized");
		}

		scope(failure) {
			_release();
		}

		int byte_size = 0;

		version (pxINCLUDE_OGGVORBIS) {
			import derelict.vorbis;

			try {
				DerelictVorbis.load();
				DerelictVorbisFile.load();
			} catch (Exception e) {
				throw new PxtoneException("Vorbis library failed to load");
			}
		}

		_ptn_bldr = pxtnPulse_NoiseBuilder.init;

		// delay
		_delays.reserve(pxtnMAX_TUNEDELAYSTRUCT);

		// over-drive
		_ovdrvs.reserve(pxtnMAX_TUNEOVERDRIVESTRUCT);

		// woice
		_woices.reserve(pxtnMAX_TUNEWOICESTRUCT);

		// unit
		_units.reserve(pxtnMAX_TUNEUNITSTRUCT);

		if (!_moo_init()) {
			throw new PxtoneException("_moo_init failed");
		}

		_b_edit = b_edit;
		_b_init = true;

	}

	void _release() @system {
		_b_init = false;

		_moo_destructer();

		_delays = null;
		_ovdrvs = null;
		_woices = null;
		_units = null;
	}

	void _moo_destructer() nothrow @system {

		_moo_release();
	}

	bool _moo_init() nothrow @system {
		bool b_ret = false;

		_moo_freq = new pxtnPulse_Frequency();
		if (!_moo_freq) {
			goto term;
		}
		_moo_group_smps = new int[](pxtnMAX_TUNEGROUPNUM);
		if (!_moo_group_smps) {
			goto term;
		}

		_moo_b_init = true;
		b_ret = true;
	term:
		if (!b_ret) {
			_moo_release();
		}

		return b_ret;
	}

	bool _moo_release() nothrow @system {
		if (!_moo_b_init) {
			return false;
		}
		_moo_b_init = false;
		_moo_freq = null;
		_moo_group_smps = null;
		return true;
	}

	////////////////////////////////////////////////
	// Units   ////////////////////////////////////
	////////////////////////////////////////////////

	bool _moo_ResetVoiceOn(pxtnUnit* p_u, int w) const nothrow @safe {
		if (!_moo_b_init) {
			return false;
		}

		const(pxtnVOICEINSTANCE)* p_inst;
		const(pxtnVOICEUNIT)* p_vc;
		const(pxtnWoice)* p_wc = Woice_Get(w);

		if (!p_wc) {
			return false;
		}

		p_u.set_woice(p_wc);

		for (int v = 0; v < p_wc.get_voice_num(); v++) {
			p_inst = p_wc.get_instance(v);
			p_vc = p_wc.get_voice(v);

			float ofs_freq = 0;
			if (p_vc.voice_flags & PTV_VOICEFLAG_BEATFIT) {
				ofs_freq = (p_inst.smp_body_w * _moo_bt_tempo) / (44100 * 60 * p_vc.tuning);
			} else {
				ofs_freq = _moo_freq.Get(EVENTDEFAULT_BASICKEY - p_vc.basic_key) * p_vc.tuning;
			}
			p_u.Tone_Reset_and_2prm(v, cast(int)(p_inst.env_release / _moo_clock_rate), ofs_freq);
		}
		return true;
	}

	bool _moo_InitUnitTone() nothrow @safe {
		if (!_moo_b_init) {
			return false;
		}
		for (int u = 0; u < _units.length; u++) {
			pxtnUnit* p_u = Unit_Get(u);
			p_u.Tone_Init();
			_moo_ResetVoiceOn(p_u, EVENTDEFAULT_VOICENO);
		}
		return true;
	}

	bool _moo_PXTONE_SAMPLE(short[] p_data) nothrow @safe {
		if (!_moo_b_init) {
			return false;
		}

		// envelope..
		for (int u = 0; u < _units.length; u++) {
			_units[u].Tone_Envelope();
		}

		int clock = cast(int)(_moo_smp_count / _moo_clock_rate);

		// events..
		for (; _moo_p_eve && _moo_p_eve.clock <= clock; _moo_p_eve = _moo_p_eve.next) {
			int u = _moo_p_eve.unit_no;
			pxtnUnit* p_u = &_units[u];
			pxtnVOICETONE* p_tone;
			const(pxtnWoice)* p_wc;
			const(pxtnVOICEINSTANCE)* p_vi;

			switch (_moo_p_eve.kind) {
			case EVENTKIND.ON: {
					int on_count = cast(int)((_moo_p_eve.clock + _moo_p_eve.value - clock) * _moo_clock_rate);
					if (on_count <= 0) {
						p_u.Tone_ZeroLives();
						break;
					}

					p_u.Tone_KeyOn();

					p_wc = p_u.get_woice();
					if (!(p_wc)) {
						break;
					}
					for (int v = 0; v < p_wc.get_voice_num(); v++) {
						p_tone = p_u.get_tone(v);
						p_vi = p_wc.get_instance(v);

						// release..
						if (p_vi.env_release) {
							int max_life_count1 = cast(int)((_moo_p_eve.value - (clock - _moo_p_eve.clock)) * _moo_clock_rate) + p_vi.env_release;
							int max_life_count2;
							int c = _moo_p_eve.clock + _moo_p_eve.value + p_tone.env_release_clock;
							const(EVERECORD)* next = null;
							for (const(EVERECORD)* p = _moo_p_eve.next; p; p = p.next) {
								if (p.clock > c) {
									break;
								}
								if (p.unit_no == u && p.kind == EVENTKIND.ON) {
									next = p;
									break;
								}
							}
							if (!next) {
								max_life_count2 = _moo_smp_end - cast(int)(clock * _moo_clock_rate);
							} else {
								max_life_count2 = cast(int)((next.clock - clock) * _moo_clock_rate);
							}
							if (max_life_count1 < max_life_count2) {
								p_tone.life_count = max_life_count1;
							} else {
								p_tone.life_count = max_life_count2;
							}
						}  // no-release..
						else {
							p_tone.life_count = cast(int)((_moo_p_eve.value - (clock - _moo_p_eve.clock)) * _moo_clock_rate);
						}

						if (p_tone.life_count > 0) {
							p_tone.on_count = on_count;
							p_tone.smp_pos = 0;
							p_tone.env_pos = 0;
							if (p_vi.env_size) {
								p_tone.env_volume = p_tone.env_start = 0; // envelope
							} else {
								p_tone.env_volume = p_tone.env_start = 128; // no-envelope
							}
						}
					}
					break;
				}

			case EVENTKIND.KEY:
				p_u.Tone_Key(_moo_p_eve.value);
				break;
			case EVENTKIND.PAN_VOLUME:
				p_u.Tone_Pan_Volume(_dst_ch_num, _moo_p_eve.value);
				break;
			case EVENTKIND.PAN_TIME:
				p_u.Tone_Pan_Time(_dst_ch_num, _moo_p_eve.value, _dst_sps);
				break;
			case EVENTKIND.VELOCITY:
				p_u.Tone_Velocity(_moo_p_eve.value);
				break;
			case EVENTKIND.VOLUME:
				p_u.Tone_Volume(_moo_p_eve.value);
				break;
			case EVENTKIND.PORTAMENT:
				p_u.Tone_Portament(cast(int)(_moo_p_eve.value * _moo_clock_rate));
				break;
			case EVENTKIND.BEATCLOCK:
				break;
			case EVENTKIND.BEATTEMPO:
				break;
			case EVENTKIND.BEATNUM:
				break;
			case EVENTKIND.REPEAT:
				break;
			case EVENTKIND.LAST:
				break;
			case EVENTKIND.VOICENO:
				_moo_ResetVoiceOn(p_u, _moo_p_eve.value);
				break;
			case EVENTKIND.GROUPNO:
				p_u.Tone_GroupNo(_moo_p_eve.value);
				break;
			case EVENTKIND.TUNING:
				p_u.Tone_Tuning(*(cast(const(float)*)(&_moo_p_eve.value)));
				break;
			default:
				break;
			}
		}

		// sampling..
		for (int u = 0; u < _units.length; u++) {
			_units[u].Tone_Sample(_moo_b_mute_by_unit, _dst_ch_num, _moo_time_pan_index, _moo_smp_smooth);
		}

		for (int ch = 0; ch < _dst_ch_num; ch++) {
			for (int g = 0; g < pxtnMAX_TUNEGROUPNUM; g++) {
				_moo_group_smps[g] = 0;
			}
			for (int u = 0; u < _units.length; u++) {
				_units[u].Tone_Supple(_moo_group_smps, ch, _moo_time_pan_index);
			}
			for (int o = 0; o < _ovdrvs.length; o++) {
				_ovdrvs[o].Tone_Supple(_moo_group_smps);
			}
			for (int d = 0; d < _delays.length; d++) {
				_delays[d].Tone_Supple(ch, _moo_group_smps);
			}

			// collect.
			int work = 0;
			for (int g = 0; g < pxtnMAX_TUNEGROUPNUM; g++) {
				work += _moo_group_smps[g];
			}

			// fade..
			if (_moo_fade_fade) {
				work = work * (_moo_fade_count >> 8) / _moo_fade_max;
			}

			// master volume
			work = cast(int)(work * _moo_master_vol);

			// to buffer..
			if (work > _moo_top) {
				work = _moo_top;
			}
			if (work < -_moo_top) {
				work = -_moo_top;
			}
			p_data[ch] = cast(short)(work);
		}

		// --------------
		// increments..

		_moo_smp_count++;
		_moo_time_pan_index = (_moo_time_pan_index + 1) & (pxtnBUFSIZE_TIMEPAN - 1);

		for (int u = 0; u < _units.length; u++) {
			int key_now = _units[u].Tone_Increment_Key();
			_units[u].Tone_Increment_Sample(_moo_freq.Get2(key_now) * _moo_smp_stride);
		}

		// delay
		for (int d = 0; d < _delays.length; d++) {
			_delays[d].Tone_Increment();
		}

		// fade out
		if (_moo_fade_fade < 0) {
			if (_moo_fade_count > 0) {
				_moo_fade_count--;
			} else {
				return false;
			}
		}  // fade in
		else if (_moo_fade_fade > 0) {
			if (_moo_fade_count < (_moo_fade_max << 8)) {
				_moo_fade_count++;
			} else {
				_moo_fade_fade = 0;
			}
		}

		if (_moo_smp_count >= _moo_smp_end) {
			if (!_moo_b_loop) {
				return false;
			}
			_moo_smp_count = _moo_smp_repeat;
			_moo_p_eve = song.evels.get_Records();
			_moo_InitUnitTone();
		}
		return true;
	}

	pxtnSampledCallback _sampled_proc;
	void* _sampled_user;

public:

	void load(const PxToneSong song) @system {
		this.song = &[song][0];
		_delays = new pxtnDelay[](song._delays.length);
		foreach (idx, ref delay; _delays) {
			const dela = song._delays[idx];
			delay.Set(cast(DELAYUNIT)dela.unit, dela.freq, dela.rate, dela.group);
		}
		_ovdrvs = new pxtnOverDrive*[](song._ovdrvs.length);
		foreach (idx, ref overdrive; _ovdrvs) {
			const songOverdrive = song._ovdrvs[idx];
			overdrive = new pxtnOverDrive;
			overdrive._b_played = songOverdrive._b_played;
			overdrive._group = songOverdrive._group;
			overdrive._cut_f = songOverdrive._cut_f;
			overdrive._amp_f = songOverdrive._amp_f;
			overdrive._cut_16bit_top = songOverdrive._cut_16bit_top;
		}
		_woices = new pxtnWoice*[](song._woices.length);
		foreach (idx, ref woice; _woices) {
			const songWoice = song._woices[idx];
			woice = new pxtnWoice;
			woice._voice_num = songWoice._voice_num;
			woice._name_buf = songWoice._name_buf;
			woice._name_size = songWoice._name_size;
			woice._type = songWoice._type;
			woice._x3x_tuning = songWoice._x3x_tuning;
			woice._x3x_basic_key = songWoice._x3x_basic_key;
			woice._voices.length = songWoice._voices.length;
			foreach (voiceIDX, ref voice; woice._voices) {
				const songVoice = songWoice._voices[voiceIDX];
				voice.basic_key = songVoice.basic_key;
				voice.volume = songVoice.volume;
				voice.pan = songVoice.pan;
				voice.tuning = songVoice.tuning;
				voice.voice_flags = songVoice.voice_flags;
				voice.data_flags = songVoice.data_flags;
				voice.type = songVoice.type;
				songVoice.p_pcm.Copy(voice.p_pcm);
				songVoice.p_ptn.Copy(voice.p_ptn);
				songVoice.p_oggv.Copy(voice.p_oggv);
				voice.wave.num = songVoice.wave.num;
				voice.wave.reso = songVoice.wave.reso;
				voice.wave.points = songVoice.wave.points.dup;
				voice.envelope.fps = songVoice.envelope.fps;
				voice.envelope.head_num = songVoice.envelope.head_num;
				voice.envelope.body_num = songVoice.envelope.body_num;
				voice.envelope.tail_num = songVoice.envelope.tail_num;
				voice.envelope.points = songVoice.envelope.points.dup;
			}
			woice._voinsts.length = songWoice._voinsts.length;
		}

		_units = song._units.dup;
		tones_ready();
		_moo_b_valid_data = true;
	}

	void initialize() @system {
		_init(0, false);
	}

	void tones_ready() @system {
		if (!_b_init) {
			throw new PxtoneException("pxtnService not initialized");
		}

		int beat_num = song.master.get_beat_num();
		float beat_tempo = song.master.get_beat_tempo();

		for (int i = 0; i < _delays.length; i++) {
			_delays[i].Tone_Ready(beat_num, beat_tempo, _dst_sps);
		}
		for (int i = 0; i < _ovdrvs.length; i++) {
			_ovdrvs[i].Tone_Ready();
		}
		for (int i = 0; i < song._woices.length; i++) {
			song._woices[i].Tone_Ready(_woices[i], _ptn_bldr, _dst_sps);
		}
	}

	bool tones_clear() nothrow @system {
		if (!_b_init) {
			return false;
		}
		for (int i = 0; i < _delays.length; i++) {
			_delays[i].Tone_Clear();
		}
		for (int i = 0; i < _units.length; i++) {
			_units[i].Tone_Clear();
		}
		return true;
	}

	int Group_Num() const nothrow @safe {
		return _b_init ? pxtnMAX_TUNEGROUPNUM : 0;
	}

	// ---------------------------
	// Delay..
	// ---------------------------

	int Delay_Num() const nothrow @safe {
		return _b_init ? cast(int)_delays.length : 0;
	}

	int Delay_Max() const nothrow @safe {
		return _b_init ? cast(int)_delays.length : 0;
	}

	bool Delay_Set(int idx, DELAYUNIT unit, float freq, float rate, int group) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (idx >= _delays.length) {
			return false;
		}
		_delays[idx].Set(unit, freq, rate, group);
		return true;
	}

	bool Delay_Add(DELAYUNIT unit, float freq, float rate, int group) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (_delays.length >= pxtnMAX_TUNEDELAYSTRUCT) {
			return false;
		}
		_delays.length++;
		_delays[$ - 1] = pxtnDelay.init;
		_delays[$ - 1].Set(unit, freq, rate, group);
		return true;
	}

	bool Delay_Remove(int idx) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (idx >= _delays.length) {
			return false;
		}

		for (int i = idx; i < _delays.length; i++) {
			_delays[i] = _delays[i + 1];
		}
		_delays.length--;
		return true;
	}

	void Delay_ReadyTone(int idx) @system {
		if (!_b_init) {
			throw new PxtoneException("pxtnService not initialized");
		}
		if (idx < 0 || idx >= _delays.length) {
			throw new PxtoneException("param");
		}
		_delays[idx].Tone_Ready(song.master.get_beat_num(), song.master.get_beat_tempo(), _dst_sps);
	}

	pxtnDelay* Delay_Get(int idx) nothrow @system {
		if (!_b_init) {
			return null;
		}
		if (idx < 0 || idx >= _delays.length) {
			return null;
		}
		return &_delays[idx];
	}

	// ---------------------------
	// Over Drive..
	// ---------------------------

	int OverDrive_Num() const nothrow @safe {
		return _b_init ? cast(int)_ovdrvs.length : 0;
	}

	int OverDrive_Max() const nothrow @safe {
		return _b_init ? cast(int)_ovdrvs.length : 0;
	}

	bool OverDrive_Set(int idx, float cut, float amp, int group) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (idx >= _ovdrvs.length) {
			return false;
		}
		_ovdrvs[idx].Set(cut, amp, group);
		return true;
	}

	bool OverDrive_Add(float cut, float amp, int group) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (_ovdrvs.length >= _ovdrvs.length) {
			return false;
		}
		_ovdrvs ~= new pxtnOverDrive();
		_ovdrvs[$ - 1].Set(cut, amp, group);
		return true;
	}

	bool OverDrive_Remove(int idx) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (idx >= _ovdrvs.length) {
			return false;
		}

		_ovdrvs[idx] = null;
		for (int i = idx; i < _ovdrvs.length; i++) {
			_ovdrvs[i] = _ovdrvs[i + 1];
		}
		_ovdrvs.length--;
		return true;
	}

	bool OverDrive_ReadyTone(int idx) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (idx < 0 || idx >= _ovdrvs.length) {
			return false;
		}
		_ovdrvs[idx].Tone_Ready();
		return true;
	}

	pxtnOverDrive* OverDrive_Get(int idx) nothrow @system {
		if (!_b_init) {
			return null;
		}
		if (idx < 0 || idx >= _ovdrvs.length) {
			return null;
		}
		return _ovdrvs[idx];
	}

	// ---------------------------
	// Woice..
	// ---------------------------

	int Woice_Num() const nothrow @safe {
		return _b_init ? cast(int)_woices.length : 0;
	}

	int Woice_Max() const nothrow @safe {
		return _b_init ? cast(int)_woices.length : 0;
	}

	inout(pxtnWoice)* Woice_Get(int idx) inout nothrow @safe {
		if (!_b_init) {
			return null;
		}
		if (idx < 0 || idx >= _woices.length) {
			return null;
		}
		return _woices[idx];
	}

	void Woice_read(int idx, ref pxtnDescriptor desc, pxtnWOICETYPE type) @system {
		if (!_b_init) {
			throw new PxtoneException("pxtnService not initialized");
		}
		if (idx < 0 || idx >= _woices.length) {
			throw new PxtoneException("param");
		}
		if (idx > _woices.length) {
			throw new PxtoneException("param");
		}
		if (idx == _woices.length) {
			_woices ~= new pxtnWoice();
		}

		scope(failure) {
			Woice_Remove(idx);
		}
		_woices[idx].read(desc, type);
	}

	void Woice_ReadyTone(int idx) @system {
		if (!_b_init) {
			throw new PxtoneException("pxtnService not initialized");
		}
		if (idx < 0 || idx >= _woices.length) {
			throw new PxtoneException("param");
		}
		song._woices[idx].Tone_Ready(_woices[idx], _ptn_bldr, _dst_sps);
	}

	bool Woice_Remove(int idx) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (idx < 0 || idx >= _woices.length) {
			return false;
		}
		_woices[idx] = null;
		for (int i = idx; i < _woices.length - 1; i++) {
			_woices[i] = _woices[i + 1];
		}
		_woices.length--;
		return true;
	}

	bool Woice_Replace(int old_place, int new_place) nothrow @system {
		if (!_b_init) {
			return false;
		}

		pxtnWoice* p_w = _woices[old_place];
		int max_place = cast(int)_woices.length - 1;

		if (new_place > max_place) {
			new_place = max_place;
		}
		if (new_place == old_place) {
			return true;
		}

		if (old_place < new_place) {
			for (int w = old_place; w < new_place; w++) {
				if (_woices[w]) {
					_woices[w] = _woices[w + 1];
				}
			}
		} else {
			for (int w = old_place; w > new_place; w--) {
				if (_woices[w]) {
					_woices[w] = _woices[w - 1];
				}
			}
		}

		_woices[new_place] = p_w;
		return true;
	}

	// ---------------------------
	// Unit..
	// ---------------------------

	int Unit_Num() const nothrow @safe {
		return _b_init ? cast(int)_units.length : 0;
	}

	int Unit_Max() const nothrow @safe {
		return _b_init ? cast(int)_units.length : 0;
	}

	inout(pxtnUnit)* Unit_Get(int idx) inout nothrow @safe {
		if (!_b_init) {
			return null;
		}
		if (idx < 0 || idx >= _units.length) {
			return null;
		}
		return &_units[idx];
	}

	bool Unit_Remove(int idx) nothrow @system {
		if (!_b_init) {
			return false;
		}
		if (idx < 0 || idx >= _units.length) {
			return false;
		}
		for (int i = idx; i < _units.length; i++) {
			_units[i] = _units[i + 1];
		}
		_units.length--;
		return true;
	}

	bool Unit_Replace(int old_place, int new_place) nothrow @system {
		if (!_b_init) {
			return false;
		}

		pxtnUnit p_w = _units[old_place];
		int max_place = cast(int)_units.length - 1;

		if (new_place > max_place) {
			new_place = max_place;
		}
		if (new_place == old_place) {
			return true;
		}

		if (old_place < new_place) {
			for (int w = old_place; w < new_place; w++) {
				_units[w] = _units[w + 1];
			}
		} else {
			for (int w = old_place; w > new_place; w--) {
				_units[w] = _units[w - 1];
			}
		}
		_units[new_place] = p_w;
		return true;
	}

	bool Unit_AddNew() nothrow @system {
		if (pxtnMAX_TUNEUNITSTRUCT < _units.length) {
			return false;
		}
		_units.length++;
		_units[$ - 1] = pxtnUnit.init;
		return true;
	}

	bool Unit_SetOpratedAll(bool b) nothrow @system {
		if (!_b_init) {
			return false;
		}
		for (int u = 0; u < _units.length; u++) {
			_units[u].set_operated(b);
			if (b) {
				_units[u].set_played(true);
			}
		}
		return true;
	}

	bool Unit_Solo(int idx) nothrow @system {
		if (!_b_init) {
			return false;
		}
		for (int u = 0; u < _units.length; u++) {
			if (u == idx) {
				_units[u].set_played(true);
			} else {
				_units[u].set_played(false);
			}
		}
		return false;
	}

	// ---------------------------
	// Quality..
	// ---------------------------

	void set_destination_quality(int ch_num, int sps) @safe {
		enforce(_b_init, new PxtoneException("pxtnService not initialized"));
		switch (ch_num) {
		case 1:
			break;
		case 2:
			break;
		default:
			throw new PxtoneException("Unsupported sample rate");
		}

		_dst_ch_num = ch_num;
		_dst_sps = sps;
	}

	void get_destination_quality(int* p_ch_num, int* p_sps) const @safe {
		enforce(_b_init, new PxtoneException("pxtnService not initialized"));
		if (p_ch_num) {
			*p_ch_num = _dst_ch_num;
		}
		if (p_sps) {
			*p_sps = _dst_sps;
		}
	}

	void set_sampled_callback(pxtnSampledCallback proc, void* user) @safe {
		enforce(_b_init, new PxtoneException("pxtnService not initialized"));
		_sampled_proc = proc;
		_sampled_user = user;
	}

	//////////////
	// Moo..
	//////////////

	///////////////////////
	// get / set
	///////////////////////

	bool moo_is_valid_data() const @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		return _moo_b_valid_data;
	}

	bool moo_is_end_vomit() const @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		return _moo_b_end_vomit;
	}

	void moo_set_mute_by_unit(bool b) @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		_moo_b_mute_by_unit = b;
	}

	void moo_set_loop(bool b) @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		_moo_b_loop = b;
	}

	void moo_set_fade(int fade, float sec) @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		_moo_fade_max = cast(int)(cast(float) _dst_sps * sec) >> 8;
		if (fade < 0) {
			_moo_fade_fade = -1;
			_moo_fade_count = _moo_fade_max << 8;
		}  // out
		else if (fade > 0) {
			_moo_fade_fade = 1;
			_moo_fade_count = 0;
		}  // in
		else {
			_moo_fade_fade = 0;
			_moo_fade_count = 0;
		} // off
	}

	void moo_set_master_volume(float v) @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		if (v < 0) {
			v = 0;
		}
		if (v > 1) {
			v = 1;
		}
		_moo_master_vol = v;
	}

	int moo_get_total_sample() const @system {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		enforce(_moo_b_valid_data, new PxtoneException("no valid data loaded"));

		int meas_num;
		int beat_num;
		float beat_tempo;
		song.master.Get(&beat_num, &beat_tempo, null, &meas_num);
		return pxtnService_moo_CalcSampleNum(meas_num, beat_num, _dst_sps, song.master.get_beat_tempo());
	}

	int moo_get_now_clock() const @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		enforce(_moo_clock_rate, new PxtoneException("No clock rate set"));
		return cast(int)(_moo_smp_count / _moo_clock_rate);
	}

	int moo_get_end_clock() const @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		enforce(_moo_clock_rate, new PxtoneException("No clock rate set"));
		return cast(int)(_moo_smp_end / _moo_clock_rate);
	}

	int moo_get_sampling_offset() const @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		enforce(!_moo_b_end_vomit, new PxtoneException("playback has ended"));
		return _moo_smp_count;
	}

	int moo_get_sampling_end() const @safe {
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		enforce(!_moo_b_end_vomit, new PxtoneException("playback has ended"));
		return _moo_smp_end;
	}

	// preparation
	void moo_preparation() @system {
		return moo_preparation(pxtnVOMITPREPARATION.init);
	}
	void moo_preparation(in pxtnVOMITPREPARATION p_prep) @system {
		scope(failure) {
			_moo_b_end_vomit = true;
		}
		enforce(_moo_b_init, new PxtoneException("pxtnService not initialized"));
		enforce(_moo_b_valid_data, new PxtoneException("no valid data loaded"));
		enforce(_dst_ch_num, new PxtoneException("invalid channel number specified"));
		enforce(_dst_sps, new PxtoneException("invalid sample rate specified"));

		int meas_end = song.master.get_play_meas();
		int meas_repeat = song.master.get_repeat_meas();

		if (p_prep.meas_end) {
			meas_end = p_prep.meas_end;
		}
		if (p_prep.meas_repeat) {
			meas_repeat = p_prep.meas_repeat;
		}

		_moo_b_mute_by_unit = p_prep.flags.unitMute;
		_moo_b_loop = p_prep.flags.loop;

		setVolume(p_prep.master_volume);

		_moo_bt_clock = song.master.get_beat_clock();
		_moo_bt_num = song.master.get_beat_num();
		_moo_bt_tempo = song.master.get_beat_tempo();
		_moo_clock_rate = cast(float)(60.0f * cast(double) _dst_sps / (cast(double) _moo_bt_tempo * cast(double) _moo_bt_clock));
		_moo_smp_stride = (44100.0f / _dst_sps);
		_moo_top = 0x7fff;

		_moo_time_pan_index = 0;

		_moo_smp_end = cast(int)(cast(double) meas_end * cast(double) _moo_bt_num * cast(double) _moo_bt_clock * _moo_clock_rate);
		_moo_smp_repeat = cast(int)(cast(double) meas_repeat * cast(double) _moo_bt_num * cast(double) _moo_bt_clock * _moo_clock_rate);

		if (p_prep.start_pos_float) {
			_moo_smp_start = cast(int)(cast(float) moo_get_total_sample() * p_prep.start_pos_float);
		} else if (p_prep.start_pos_sample) {
			_moo_smp_start = p_prep.start_pos_sample;
		} else {
			_moo_smp_start = cast(int)(cast(double) p_prep.start_pos_meas * cast(double) _moo_bt_num * cast(double) _moo_bt_clock * _moo_clock_rate);
		}

		_moo_smp_count = _moo_smp_start;
		_moo_smp_smooth = _dst_sps / 250; // (0.004sec) // (0.010sec)

		if (p_prep.fadein_sec > 0) {
			moo_set_fade(1, p_prep.fadein_sec);
		} else {
			moo_set_fade(0, 0);
		}
		start();
	}

	void setVolume(float volume) @system {
		enforce(!volume.isNaN, "Volume must be a number");
		_moo_master_vol = clamp(volume, 0.0, 1.0);
	}

	void start() @system {
		tones_clear();

		_moo_p_eve = song.evels.get_Records();

		_moo_InitUnitTone();

		_moo_b_end_vomit = false;
	}

	////////////////////
	//
	////////////////////

	bool Moo(short[] p_buf) nothrow @system {
		if (!_moo_b_init) {
			return false;
		}
		if (!_moo_b_valid_data) {
			return false;
		}
		if (_moo_b_end_vomit) {
			return false;
		}

		bool b_ret = false;

		int smp_w = 0;

		if (p_buf.length % _dst_ch_num) {
			return false;
		}

		int smp_num = cast(int)(p_buf.length / _dst_ch_num);

		{
			short[2] sample;

			for (smp_w = 0; smp_w < smp_num; smp_w++) {
				if (!_moo_PXTONE_SAMPLE(sample[])) {
					_moo_b_end_vomit = true;
					break;
				}
				for (int ch = 0; ch < _dst_ch_num; ch++, p_buf = p_buf[1 .. $]) {
					p_buf[0] = sample[ch];
				}
			}
			for (; smp_w < smp_num; smp_w++) {
				for (int ch = 0; ch < _dst_ch_num; ch++, p_buf = p_buf[1 .. $]) {
					p_buf[0] = 0;
				}
			}
		}

		if (_sampled_proc) {
			int clock = cast(int)(_moo_smp_count / _moo_clock_rate);
			if (!_sampled_proc(_sampled_user, &this)) {
				_moo_b_end_vomit = true;
				goto term;
			}
		}

		b_ret = true;
	term:
		return b_ret;
	}
}

int pxtnService_moo_CalcSampleNum(int meas_num, int beat_num, int sps, float beat_tempo) nothrow @safe {
	uint total_beat_num;
	uint sample_num;
	if (!beat_tempo) {
		return 0;
	}
	total_beat_num = meas_num * beat_num;
	sample_num = cast(uint)(cast(double) sps * 60 * cast(double) total_beat_num / cast(double) beat_tempo);
	return sample_num;
}
