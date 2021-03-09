import core.sys.windows.windows;
import core.sys.windows.shlwapi;

import pxtone;

import core.stdc.stdlib;
import core.stdc.string;

import std.file;
import std.format;
import std.path;

static const TCHAR* _app_name = "pxtone-play-sample"w.ptr;

extern(C) FILE* _wfopen(const(wchar_t)*, const(wchar_t)*);
extern(C) int fclose(FILE*);

extern(C) int swprintf_s(wchar_t*,size_t,const(wchar_t) *,...);
alias _stprintf_s = swprintf_s;

enum _CHANNEL_NUM = 2;
enum _SAMPLE_PER_SECOND = 48000;
enum _BUFFER_PER_SEC = (0.3f);

import std.experimental.logger;
import std.string;
import bindbc.sdl : SDL_AudioCallback, SDL_AudioDeviceID;

static bool _load_ptcop( pxtnService* pxtn, void[] data, pxtnERR* p_pxtn_err )
{
	bool           b_ret     = false;
	pxtnDescriptor* desc = allocate!pxtnDescriptor();
	pxtnERR        pxtn_err  = pxtnERR.pxtnERR_VOID;

	if( !desc.set_memory_r( data.ptr, cast(int)data.length ) ) goto term;

	pxtn_err = pxtn.read       ( desc ); if( pxtn_err != pxtnERR.pxtnOK ) goto term;
	pxtn_err = pxtn.tones_ready(       ); if( pxtn_err != pxtnERR.pxtnOK ) goto term;

	b_ret = true;
term:

	if( !b_ret ) pxtn.evels.Release();

	if( p_pxtn_err ) *p_pxtn_err = pxtn_err;

	return b_ret;
}

__gshared SDL_AudioDeviceID dev;

bool initAudio(SDL_AudioCallback fun, ubyte channels, uint sampleRate, void* userdata = null) {
	import bindbc.sdl;
	import core.stdc.stdio;
    assert(loadSDL() == sdlSupport);
    if (SDL_Init(SDL_INIT_AUDIO) != 0) {
        fprintf(stderr, "SDL init failed: %s\n", SDL_GetError());
        return false;
    }
    SDL_AudioSpec want, have;
    want.freq = sampleRate;
    want.format = SDL_AudioFormat.AUDIO_S16;
    want.channels = channels;
    want.samples = 512;
    want.callback = fun;
    want.userdata = userdata;
    dev = SDL_OpenAudioDevice(null, 0, &want, &have, 0);
    if (dev == 0) {
        fprintf(stderr, "SDL_OpenAudio failed: %s\n", SDL_GetError());
        return false;
    }
    SDL_PauseAudioDevice(dev, 0);
    return true;
}

// Shift-JIS to UNICODE.
static bool _sjis_to_wide( const char*    p_src, wchar** pp_dst, int* p_dst_num  )
{
	bool     b_ret     = false;
	wchar* p_wide    = null ;
	int      num_wide  =     0;

	if( !p_src    ) return false;
	if( p_dst_num ) *p_dst_num = 0;
	*pp_dst = null;

	// to UTF-16
	num_wide = MultiByteToWideChar( CP_ACP, 0, p_src, -1, null, 0 );
	if( !( num_wide ) ) goto term;
	p_wide = cast(wchar*)malloc( num_wide * wchar.sizeof );
	if( !( p_wide  )         ) goto term;
	memset( p_wide, 0,                 num_wide * wchar.sizeof );
	if( !MultiByteToWideChar( CP_ACP, 0, p_src, -1, p_wide, num_wide )        ) goto term;

	if( p_dst_num ) *p_dst_num = num_wide - 1; // remove last ' '
	*pp_dst = p_wide;

	b_ret = true;
term:
	if( !b_ret ) free( p_wide );

	return b_ret;
}

extern(C) void _sampling_func( void *user, ubyte *buf, int bufSize) nothrow {
	pxtnService* pxtn = cast(pxtnService*)user;
	pxtn.Moo( buf[0 .. bufSize] );
}

int main(string[] args)
{
	if (args.length < 2) {
		return 1;
	}

	bool           b_ret    = false;
	pxtnService*   pxtn     = null ;
	pxtnERR        pxtn_err = pxtnERR.pxtnERR_VOID;

	import std.utf : toUTF16z;
	auto filePath = args[1];
	auto file = read(args[1]);

	// INIT PXTONE.
	pxtn = allocate!pxtnService();
	pxtn_err = pxtn.init_(); if( pxtn_err != pxtnERR.pxtnOK ) goto term;
	if( !pxtn.set_destination_quality( _CHANNEL_NUM, _SAMPLE_PER_SECOND ) ) goto term;

	// LOAD MUSIC FILE.
	if( !_load_ptcop( pxtn, file, &pxtn_err ) ) goto term;

	// PREPARATION PLAYING MUSIC.
	{
		//int smp_total = pxtn.moo_get_total_sample();

		pxtnVOMITPREPARATION prep;
		prep.flags          |= pxtnVOMITPREPFLAG_loop;
		prep.start_pos_float =     0;
		prep.master_volume   = 0.80f;

		if( !pxtn.moo_preparation( &prep ) ) goto term;
	}
	if (!initAudio(&_sampling_func, _CHANNEL_NUM, _SAMPLE_PER_SECOND, pxtn)) {
		return 1;
	}
	tracef("SDL audio init success");

	{
		char[250] text = 0;

		auto name = pxtn.text.get_name_buf();
		auto comment = pxtn.text.get_comment_buf();

		auto str = sformat(text, "file: %s\nname: %s\ncomment: %s", filePath.baseName, name, comment);

		//if( name_t ) free( name_t );
		import std.stdio : readln, writeln;
		writeln(str);
		writeln("Press enter to exit");
		readln();
	}
	b_ret = true;
term:

	if( !b_ret )
	{
		errorf("ERROR: pxtnERR[ %s ]", pxtnError_get_string( pxtn_err ).fromStringz );
		return -1;
	}
	SAFE_DELETE( pxtn );
	return 0;
}
