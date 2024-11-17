module m4a.cgb_audio;

import m4a.cgb_tables;
import m4a.internal;

struct AudioCGB {
    ushort ch1Freq;
    ubyte ch1SweepCounter;
    ubyte ch1SweepCounterI;
    ubyte ch1SweepDir;
    ubyte ch1SweepShift;
    ubyte[4] Vol;
    ubyte[4] VolI;
    ubyte[4] Len;
    ubyte[4] LenI;
    ubyte[4] LenOn;
    ubyte[4] EnvCounter;
    ubyte[4] EnvCounterI;
    ubyte[4] EnvDir;
    ubyte[4] DAC;
    float[32] WAVRAM = 0;
    ushort [2] ch4LFSR = [0x8000, 0x80];

    float[4] soundChannelPos = [0, 1, 0, 0];
    const(short)[] PU1Table = PU0;
    const(short)[] PU2Table = PU0;
    uint apuFrame;
    uint sampleRate;
    ushort[2] lfsrMax = [0x8000, 0x80];
    float ch4Samples = 0;
    ubyte apuCycle;
    void initialize(uint rate) @safe pure {
        this = this.init;
        sampleRate = rate;
    }
    void set_sweep(ubyte sweep) @safe pure {
        ch1SweepDir = (sweep & 0x08) >> 3;
        ch1SweepCounter = ch1SweepCounterI = (sweep & 0x70) >> 4;
        ch1SweepShift = (sweep & 0x07);
    }
    void set_wavram(ubyte[] wavePointer) @safe pure {
        for(ubyte wavi = 0; wavi < 0x10; wavi++){
            WAVRAM[(wavi << 1)] = ((wavePointer[wavi] & 0xF0) >> 4) / 7.5f - 1.0f;
            WAVRAM[(wavi << 1) + 1] = ((wavePointer[wavi] & 0x0F)) / 7.5f - 1.0f;
        }
    }
    void toggle_length(ubyte channel, ubyte state) @safe pure {
        LenOn[channel] = state;
    }
    void set_length(ubyte channel, ubyte length) @safe pure {
        Len[channel] = LenI[channel] = length;
    }
    void set_envelope(ubyte channel, ubyte envelope) @safe pure {
        if(channel == 2){
            switch((envelope & 0xE0)){
                case 0x00:  // mute
                    Vol[2] = VolI[2] = 0;
                break;
                case 0x20:  // full
                    Vol[2] = VolI[2] = 4;
                break;
                case 0x40:  // half
                    Vol[2] = VolI[2] = 2;
                break;
                case 0x60:  // quarter
                    Vol[2] = VolI[2] = 1;
                break;
                case 0x80:  // 3 quarters
                    Vol[2] = VolI[2] = 3;
                break;
            	default: break;
            }
        }else{
            DAC[channel] = (envelope & 0xF8) > 0;
            Vol[channel] = VolI[channel] = (envelope & 0xF0) >> 4;
            EnvDir[channel] = (envelope & 0x08) >> 3;
            EnvCounter[channel] = EnvCounterI[channel] = (envelope & 0x07);
        }
    }
    void trigger_note(ubyte channel) @safe pure {
        Vol[channel] = VolI[channel];
        Len[channel] = LenI[channel];
        if(channel != 2) EnvCounter[channel] = EnvCounterI[channel];
        if(channel == 3) {
            ch4LFSR[0] = 0x8000;
            ch4LFSR[1] = 0x80;
        }
    }
    void audio_generate(SoundMixerState *soundInfo, ushort samplesPerFrame, float[2][] outBuffer) @safe pure {
        switch(soundInfo.reg.NR11 & 0xC0){
            case 0x00:
                PU1Table = PU0;
            break;
            case 0x40:
                PU1Table = PU1;
            break;
            case 0x80:
                PU1Table = PU2;
            break;
            case 0xC0:
                PU1Table = PU3;
            break;
            default: break;
        }

        switch(soundInfo.reg.NR21 & 0xC0){
            case 0x00:
                PU2Table = PU0;
            break;
            case 0x40:
                PU2Table = PU1;
            break;
            case 0x80:
                PU2Table = PU2;
            break;
            case 0xC0:
                PU2Table = PU3;
            break;
            default: break;
        }

        for (ushort i = 0; i < samplesPerFrame; i++, outBuffer = outBuffer[1 .. $]) {
            apuFrame += 512;
            if(apuFrame >= sampleRate){
                apuFrame -= sampleRate;
                apuCycle++;

                if((apuCycle & 1) == 0){  // Length
                    for(ubyte ch = 0; ch < 4; ch++){
                        if(Len[ch]){
                            if(--Len[ch] == 0 && LenOn[ch]){
                                soundInfo.reg.NR52 &= (0xFF ^ (1 << ch));
                            }
                        }
                    }
                }

                if((apuCycle & 7) == 7){  // Envelope
                    for(ubyte ch = 0; ch < 4; ch++){
                        if(ch == 2) continue;  // Skip wave channel
                        if(EnvCounter[ch]){
                            if(--EnvCounter[ch] == 0){
                                if(Vol[ch] && !EnvDir[ch]){
                                    Vol[ch]--;
                                    EnvCounter[ch] = EnvCounterI[ch];
                                }else if(Vol[ch] < 0x0F && EnvDir[ch]){
                                    Vol[ch]++;
                                    EnvCounter[ch] = EnvCounterI[ch];
                                }
                            }
                        }
                    }
                }

                if((apuCycle & 3) == 2){  // Sweep
                    if(ch1SweepCounterI && ch1SweepShift){
                        if(--ch1SweepCounter == 0){
                            ch1Freq = soundInfo.reg.SOUND1CNT_X & 0x7FF;
                            if(ch1SweepDir){
                                ch1Freq -= ch1Freq >> ch1SweepShift;
                                if(ch1Freq & 0xF800) ch1Freq = 0;
                            }else{
                                ch1Freq += ch1Freq >> ch1SweepShift;
                                if(ch1Freq & 0xF800){
                                    ch1Freq = 0;
                                    EnvCounter[0] = 0;
                                    Vol[0] = 0;
                                }
                            }
                            soundInfo.reg.SOUND1CNT_X &= 0xF800;
                            soundInfo.reg.SOUND1CNT_X |= ch1Freq & 0x7FF;
                            ch1SweepCounter = ch1SweepCounterI;
                        }
                    }
                }
            }
            //Sound generation loop
            soundChannelPos[0] += freqTable[soundInfo.reg.SOUND1CNT_X & 0x7FF] / (sampleRate / 32);
            soundChannelPos[1] += freqTable[soundInfo.reg.SOUND2CNT_H & 0x7FF] / (sampleRate / 32);
            soundChannelPos[2] += freqTable[soundInfo.reg.SOUND3CNT_X & 0x7FF] / (sampleRate / 32);
            while(soundChannelPos[0] >= 32) soundChannelPos[0] -= 32;
            while(soundChannelPos[1] >= 32) soundChannelPos[1] -= 32;
            while(soundChannelPos[2] >= 32) soundChannelPos[2] -= 32;
            float outputL = 0;
            float outputR = 0;
            if(soundInfo.reg.NR52 & 0x80){
                if((DAC[0]) && (soundInfo.reg.NR52 & 0x01)){
                    if(soundInfo.reg.NR51 & 0x10) outputL += Vol[0] * PU1Table[cast(int)(soundChannelPos[0])] / 15.0f;
                    if(soundInfo.reg.NR51 & 0x01) outputR += Vol[0] * PU1Table[cast(int)(soundChannelPos[0])] / 15.0f;
                }
                if((DAC[1]) && (soundInfo.reg.NR52 & 0x02)){
                    if(soundInfo.reg.NR51 & 0x20) outputL += Vol[1] * PU2Table[cast(int)(soundChannelPos[1])] / 15.0f;
                    if(soundInfo.reg.NR51 & 0x02) outputR += Vol[1] * PU2Table[cast(int)(soundChannelPos[1])] / 15.0f;
                }
                if((soundInfo.reg.NR30 & 0x80) && (soundInfo.reg.NR52 & 0x04)){
                    if(soundInfo.reg.NR51 & 0x40) outputL += Vol[2] * WAVRAM[cast(int)(soundChannelPos[2])] / 4.0f;
                    if(soundInfo.reg.NR51 & 0x04) outputR += Vol[2] * WAVRAM[cast(int)(soundChannelPos[2])] / 4.0f;
                }
                if((DAC[3]) && (soundInfo.reg.NR52 & 0x08)){
                    uint lfsrMode = !!(soundInfo.reg.NR43 & 0x08);
                    ch4Samples += freqTableNSE[soundInfo.reg.NR43] / sampleRate;
                    int ch4Out = 0;
                    if(ch4LFSR[lfsrMode] & 1){
                        ch4Out++;
                    }else{
                        ch4Out--;
                    }
                    float avgDiv = 1.0f;
                    while(ch4Samples >= 1){
                        avgDiv += 1.0f;
                        ubyte lfsrCarry = 0;
                        if(ch4LFSR[lfsrMode] & 2) lfsrCarry ^= 1;
                        ch4LFSR[lfsrMode] >>= 1;
                        if(ch4LFSR[lfsrMode] & 2) lfsrCarry ^= 1;
                        if(lfsrCarry) ch4LFSR[lfsrMode] |= lfsrMax[lfsrMode];
                        if(ch4LFSR[lfsrMode] & 1){
                            ch4Out++;
                        }else{
                            ch4Out--;
                        }
                        ch4Samples--;
                    }
                    float sample = ch4Out;
                    if(avgDiv > 1) sample /= avgDiv;
                    if(soundInfo.reg.NR51 & 0x80) outputL += (Vol[3] * sample) / 15.0f;
                    if(soundInfo.reg.NR51 & 0x08) outputR += (Vol[3] * sample) / 15.0f;
                }
            }
            outBuffer[0][0] = outputL / 4.0f;
            outBuffer[0][1] = outputR / 4.0f;
        }
    }
}

__gshared AudioCGB gb;
