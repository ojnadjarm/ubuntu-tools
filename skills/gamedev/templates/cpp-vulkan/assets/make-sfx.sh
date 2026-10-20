#!/usr/bin/env bash
# Synthesizes the game's CC0 one-shot clips (48 kHz mono 16-bit WAV): pickup chime above 1.5 kHz, goal arpeggio and footstep below 1 kHz.
set -euo pipefail
cd "$(dirname "$0")"
gen() { ffmpeg -v error -y -f lavfi -i "aevalsrc='$2':s=48000:d=$3" ${4:+-af "$4"} -c:a pcm_s16le "$1"; }
ramp='min(1,t/0.008)'
gen pickup.wav "$ramp*(0.5*sin(2*PI*1760*t)*exp(-14*t)+0.5*gt(t,0.07)*min(1,(t-0.07)/0.008)*sin(2*PI*2637*t)*exp(-12*(t-0.07)))" 0.45
gen goal.wav "$ramp*0.25*(sin(2*PI*392*t)*exp(-3*t)+gt(t,0.12)*min(1,(t-0.12)/0.008)*sin(2*PI*523*t)*exp(-3*(t-0.12))+gt(t,0.24)*min(1,(t-0.24)/0.008)*sin(2*PI*659*t)*exp(-3*(t-0.24))+gt(t,0.36)*min(1,(t-0.36)/0.008)*sin(2*PI*784*t)*exp(-3*(t-0.36)))" 1.6
gen step.wav "$ramp*(0.6*sin(2*PI*70*t)+0.4*(random(0)*2-1))*exp(-30*t)" 0.18 "lowpass=f=250,lowpass=f=250,lowpass=f=250"
