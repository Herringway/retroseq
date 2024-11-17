module m4a.cgb_audio;

import m4a.cgb_tables;
import m4a.internal;
import m4a.m4a;

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
    float[32] WAVRAM;
    ushort [2] ch4LFSR;
}

__gshared AudioCGB gb;
__gshared float[4] soundChannelPos;
__gshared const(short) *PU1Table;
__gshared const(short) *PU2Table;
__gshared uint apuFrame;
__gshared ubyte apuCycle;
__gshared uint sampleRate;
__gshared ushort[2] lfsrMax;
__gshared float ch4Samples;

void cgb_audio_init(uint rate){
    gb.ch1Freq = 0;
    gb.ch1SweepCounter = 0;
    gb.ch1SweepCounterI = 0;
    gb.ch1SweepDir = 0;
    gb.ch1SweepShift = 0;
    for (ubyte ch = 0; ch < 4; ch++){
        gb.Vol[ch] = 0;
        gb.VolI[ch] = 0;
        gb.Len[ch] = 0;
        gb.LenI[ch] = 0;
        gb.LenOn[ch] = 0;
        gb.EnvCounter[ch] = 0;
        gb.EnvCounterI[ch] = 0;
        gb.EnvDir[ch] = 0;
        gb.DAC[ch] = 0;
        soundChannelPos[ch] = 0;
    }
    soundChannelPos[1] = 1;
    PU1Table = &PU0[0];
    PU2Table = &PU0[0];
    sampleRate = rate;
    gb.ch4LFSR[0] = 0x8000;
    gb.ch4LFSR[1] = 0x80;
    lfsrMax[0] = 0x8000;
    lfsrMax[1] = 0x80;
    ch4Samples = 0.0f;
}


void cgb_set_sweep(ubyte sweep){
    gb.ch1SweepDir = (sweep & 0x08) >> 3;
    gb.ch1SweepCounter = gb.ch1SweepCounterI = (sweep & 0x70) >> 4;
    gb.ch1SweepShift = (sweep & 0x07);
}


void cgb_set_wavram(ubyte *wavePointer){
    for(ubyte wavi = 0; wavi < 0x10; wavi++){
        gb.WAVRAM[(wavi << 1)] = (((*(wavePointer + wavi)) & 0xF0) >> 4) / 7.5f - 1.0f;
        gb.WAVRAM[(wavi << 1) + 1] = (((*(wavePointer + wavi)) & 0x0F)) / 7.5f - 1.0f;
    }
}


void cgb_toggle_length(ubyte channel, ubyte state){
    gb.LenOn[channel] = state;
}


void cgb_set_length(ubyte channel, ubyte length){
    gb.Len[channel] = gb.LenI[channel] = length;
}


void cgb_set_envelope(ubyte channel, ubyte envelope){
    if(channel == 2){
        switch((envelope & 0xE0)){
            case 0x00:  // mute
                gb.Vol[2] = gb.VolI[2] = 0;
            break;
            case 0x20:  // full
                gb.Vol[2] = gb.VolI[2] = 4;
            break;
            case 0x40:  // half
                gb.Vol[2] = gb.VolI[2] = 2;
            break;
            case 0x60:  // quarter
                gb.Vol[2] = gb.VolI[2] = 1;
            break;
            case 0x80:  // 3 quarters
                gb.Vol[2] = gb.VolI[2] = 3;
            break;
        	default: break;
        }
    }else{
        gb.DAC[channel] = (envelope & 0xF8) > 0;
        gb.Vol[channel] = gb.VolI[channel] = (envelope & 0xF0) >> 4;
        gb.EnvDir[channel] = (envelope & 0x08) >> 3;
        gb.EnvCounter[channel] = gb.EnvCounterI[channel] = (envelope & 0x07);
    }
}


void cgb_trigger_note(ubyte channel){
    gb.Vol[channel] = gb.VolI[channel];
    gb.Len[channel] = gb.LenI[channel];
    if(channel != 2) gb.EnvCounter[channel] = gb.EnvCounterI[channel];
    if(channel == 3) {
        gb.ch4LFSR[0] = 0x8000;
        gb.ch4LFSR[1] = 0x80;
    }
}


void cgb_audio_generate(SoundMixerState *soundInfo, ushort samplesPerFrame, float *outBuffer){
    switch(soundInfo.reg.NR11 & 0xC0){
        case 0x00:
            PU1Table = &PU0[0];
        break;
        case 0x40:
            PU1Table = &PU1[0];
        break;
        case 0x80:
            PU1Table = &PU2[0];
        break;
        case 0xC0:
            PU1Table = &PU3[0];
        break;
        default: break;
    }

    switch(soundInfo.reg.NR21 & 0xC0){
        case 0x00:
            PU2Table = &PU0[0];
        break;
        case 0x40:
            PU2Table = &PU1[0];
        break;
        case 0x80:
            PU2Table = &PU2[0];
        break;
        case 0xC0:
            PU2Table = &PU3[0];
        break;
        default: break;
    }

    for (ushort i = 0; i < samplesPerFrame; i++, outBuffer+=2) {
        apuFrame += 512;
        if(apuFrame >= sampleRate){
            apuFrame -= sampleRate;
            apuCycle++;

            if((apuCycle & 1) == 0){  // Length
                for(ubyte ch = 0; ch < 4; ch++){
                    if(gb.Len[ch]){
                        if(--gb.Len[ch] == 0 && gb.LenOn[ch]){
                            soundInfo.reg.NR52 &= (0xFF ^ (1 << ch));
                        }
                    }
                }
            }

            if((apuCycle & 7) == 7){  // Envelope
                for(ubyte ch = 0; ch < 4; ch++){
                    if(ch == 2) continue;  // Skip wave channel
                    if(gb.EnvCounter[ch]){
                        if(--gb.EnvCounter[ch] == 0){
                            if(gb.Vol[ch] && !gb.EnvDir[ch]){
                                gb.Vol[ch]--;
                                gb.EnvCounter[ch] = gb.EnvCounterI[ch];
                            }else if(gb.Vol[ch] < 0x0F && gb.EnvDir[ch]){
                                gb.Vol[ch]++;
                                gb.EnvCounter[ch] = gb.EnvCounterI[ch];
                            }
                        }
                    }
                }
            }

            if((apuCycle & 3) == 2){  // Sweep
                if(gb.ch1SweepCounterI && gb.ch1SweepShift){
                    if(--gb.ch1SweepCounter == 0){
                        gb.ch1Freq = soundInfo.reg.SOUND1CNT_X & 0x7FF;
                        if(gb.ch1SweepDir){
                            gb.ch1Freq -= gb.ch1Freq >> gb.ch1SweepShift;
                            if(gb.ch1Freq & 0xF800) gb.ch1Freq = 0;
                        }else{
                            gb.ch1Freq += gb.ch1Freq >> gb.ch1SweepShift;
                            if(gb.ch1Freq & 0xF800){
                                gb.ch1Freq = 0;
                                gb.EnvCounter[0] = 0;
                                gb.Vol[0] = 0;
                            }
                        }
                        soundInfo.reg.SOUND1CNT_X &= 0xF800;
                        soundInfo.reg.SOUND1CNT_X |= gb.ch1Freq & 0x7FF;
                        gb.ch1SweepCounter = gb.ch1SweepCounterI;
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
            if((gb.DAC[0]) && (soundInfo.reg.NR52 & 0x01)){
                if(soundInfo.reg.NR51 & 0x10) outputL += gb.Vol[0] * PU1Table[cast(int)(soundChannelPos[0])] / 15.0f;
                if(soundInfo.reg.NR51 & 0x01) outputR += gb.Vol[0] * PU1Table[cast(int)(soundChannelPos[0])] / 15.0f;
            }
            if((gb.DAC[1]) && (soundInfo.reg.NR52 & 0x02)){
                if(soundInfo.reg.NR51 & 0x20) outputL += gb.Vol[1] * PU2Table[cast(int)(soundChannelPos[1])] / 15.0f;
                if(soundInfo.reg.NR51 & 0x02) outputR += gb.Vol[1] * PU2Table[cast(int)(soundChannelPos[1])] / 15.0f;
            }
            if((soundInfo.reg.NR30 & 0x80) && (soundInfo.reg.NR52 & 0x04)){
                if(soundInfo.reg.NR51 & 0x40) outputL += gb.Vol[2] * gb.WAVRAM[cast(int)(soundChannelPos[2])] / 4.0f;
                if(soundInfo.reg.NR51 & 0x04) outputR += gb.Vol[2] * gb.WAVRAM[cast(int)(soundChannelPos[2])] / 4.0f;
            }
            if((gb.DAC[3]) && (soundInfo.reg.NR52 & 0x08)){
                uint lfsrMode = !!(soundInfo.reg.NR43 & 0x08);
                ch4Samples += freqTableNSE[soundInfo.reg.NR43] / sampleRate;
                int ch4Out = 0;
                if(gb.ch4LFSR[lfsrMode] & 1){
                    ch4Out++;
                }else{
                    ch4Out--;
                }
                float avgDiv = 1.0f;
                while(ch4Samples >= 1){
                    avgDiv += 1.0f;
                    ubyte lfsrCarry = 0;
                    if(gb.ch4LFSR[lfsrMode] & 2) lfsrCarry ^= 1;
                    gb.ch4LFSR[lfsrMode] >>= 1;
                    if(gb.ch4LFSR[lfsrMode] & 2) lfsrCarry ^= 1;
                    if(lfsrCarry) gb.ch4LFSR[lfsrMode] |= lfsrMax[lfsrMode];
                    if(gb.ch4LFSR[lfsrMode] & 1){
                        ch4Out++;
                    }else{
                        ch4Out--;
                    }
                    ch4Samples--;
                }
                float sample = ch4Out;
                if(avgDiv > 1) sample /= avgDiv;
                if(soundInfo.reg.NR51 & 0x80) outputL += (gb.Vol[3] * sample) / 15.0f;
                if(soundInfo.reg.NR51 & 0x08) outputR += (gb.Vol[3] * sample) / 15.0f;
            }
        }
        outBuffer[0] = outputL / 4.0f;
        outBuffer[1] = outputR / 4.0f;
    }
}

