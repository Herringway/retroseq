﻿module pxtone.delay;

import pxtone.pxtn;

import pxtone.descriptor;
import pxtone.error;
import pxtone.max;
import pxtone.mem;

import core.stdc.stdlib;
import core.stdc.string;

enum DELAYUNIT
{
	DELAYUNIT_Beat = 0,
	DELAYUNIT_Meas    ,
	DELAYUNIT_Second  ,
	DELAYUNIT_num     ,
};


// (12byte) =================
struct _DELAYSTRUCT
{
	ushort unit ;
	ushort group;
	float    rate ;
	float    freq ;
}

struct pxtnDelay
{
private:
	bool      _b_played = true;
	DELAYUNIT _unit = DELAYUNIT.DELAYUNIT_Beat;
	int   _group = 0;
	float     _rate = 33.0;
	float     _freq = 3.0f;

	int   _smp_num = 0;
	int   _offset = 0;
	int*[ pxtnMAX_CHANNEL ]  _bufs = null;
	int   _rate_s32 = 0;

public :

	~this() nothrow
	{
		Tone_Release();
	}

	DELAYUNIT get_unit () const nothrow { return _unit ; }
	int   get_group() const nothrow { return _group; }
	float     get_rate () const nothrow { return _rate ; }
	float     get_freq () const nothrow { return _freq ; }

	void      Set( DELAYUNIT unit, float freq, float rate, int group )
	{
		_unit  = unit ;
		_group = group;
		_rate  = rate ;
		_freq  = freq ;
	}

	bool get_played() const nothrow{ return _b_played; }
	void set_played( bool b ) nothrow { _b_played = b; }
	bool switch_played() nothrow { _b_played = _b_played ? false : true; return _b_played; }



	void Tone_Release() nothrow
	{
		for( int i = 0; i < pxtnMAX_CHANNEL; i ++ ) pxtnMem_free( cast(void**)&_bufs[ i ] );
		_smp_num = 0;
	}

	pxtnERR Tone_Ready( int beat_num, float beat_tempo, int sps ) nothrow
	{
		Tone_Release();

		pxtnERR res = pxtnERR.pxtnERR_VOID;

		if( _freq && _rate )
		{
			_offset   = 0;
			_rate_s32 = cast(int)_rate; // /100;

			switch( _unit )
			{
			case DELAYUNIT.DELAYUNIT_Beat  : _smp_num = cast(int)( sps * 60            / beat_tempo / _freq ); break;
			case DELAYUNIT.DELAYUNIT_Meas  : _smp_num = cast(int)( sps * 60 * beat_num / beat_tempo / _freq ); break;
			case DELAYUNIT.DELAYUNIT_Second: _smp_num = cast(int)( sps                              / _freq ); break;
			default: break;
			}

			for( int c = 0; c < pxtnMAX_CHANNEL; c++ )
			{
				if( !pxtnMem_zero_alloc( cast(void**)&_bufs[ c ], _smp_num * int.sizeof ) ){ res = pxtnERR.pxtnERR_memory; goto term; }
			}
		}

		res = pxtnERR.pxtnOK;
	term:

		if( res != pxtnERR.pxtnOK ) Tone_Release();

		return res;
	}

	void Tone_Supple( int ch, int *group_smps ) nothrow
	{
		if( !_smp_num ) return;
		int a = _bufs[ ch ][ _offset ] * _rate_s32/ 100;
		if( _b_played ) group_smps[ _group ] += a;
		_bufs[ ch ][ _offset ] =  group_smps[ _group ];
	}

	void Tone_Increment() nothrow
	{
		if( !_smp_num ) return;
		if( ++_offset >= _smp_num ) _offset = 0;
	}

	void  Tone_Clear() nothrow
	{
		if( !_smp_num ) return;
		int def = 0; // ..
		for( int i = 0; i < pxtnMAX_CHANNEL; i ++ ) memset( _bufs[ i ], def, _smp_num * int.sizeof );
	}




	bool Write( pxtnDescriptor *p_doc ) const nothrow
	{
		_DELAYSTRUCT    dela;
		int            size;

		memset( &dela, 0,  _DELAYSTRUCT.sizeof );
		dela.unit  = cast(ushort)_unit ;
		dela.group = cast(ushort)_group;
		dela.rate  = _rate;
		dela.freq  = _freq;

		// dela ----------
		size =  _DELAYSTRUCT.sizeof;
		if( !p_doc.w_asfile( &size, int.sizeof, 1 ) ) return false;
		if( !p_doc.w_asfile( &dela, size,            1 ) ) return false;

		return true;
	}

	pxtnERR Read( pxtnDescriptor *p_doc ) nothrow
	{
		_DELAYSTRUCT dela = {0};
		int      size =  0 ;

		if( !p_doc.r( &size, 4,                    1 ) ) return pxtnERR.pxtnERR_desc_r     ;
		if( !p_doc.r( &dela, _DELAYSTRUCT.sizeof, 1 ) ) return pxtnERR.pxtnERR_desc_r     ;
		if( dela.unit >= DELAYUNIT.DELAYUNIT_num                  ) return pxtnERR.pxtnERR_fmt_unknown;

		_unit  = cast(DELAYUNIT)dela.unit;
		_freq  = dela.freq ;
		_rate  = dela.rate ;
		_group = dela.group;

		if( _group >= pxtnMAX_TUNEGROUPNUM ) _group = 0;

		return pxtnERR.pxtnOK;
	}
}