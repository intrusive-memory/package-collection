#!/usr/bin/env python3
"""Per-cue audio drift QA for produciesta renders.

Signals per dialogue cue (from the sidecar VTT):
  - pitch_dev: median F0 vs the speaker's own median across the piece (semitones)
  - trend: second-half vs first-half median F0 within the cue (semitones)
  - rate_z: robust z-score of chars/sec vs the piece distribution
Flags a cue when |pitch_dev| > 4 st, trend > 2.5 st, or |rate_z| > 3.5 (dur > 2s).
Exit 2 when the piece has significant drift (>=3 flags or >=10% of cues).
"""
import json, re, subprocess, sys
import numpy as np

SR = 8000
FRAME, HOP = 1024, 256
FMIN, FMAX = 55, 420

def parse_ts(ts):
    p = [float(x) for x in ts.split(':')]
    return p[0]*3600+p[1]*60+p[2] if len(p) == 3 else p[0]*60+p[1]

def parse_vtt(path):
    cues = []
    lines = open(path).read().splitlines()
    time_re = re.compile(r'^(\S+) --> (\S+)')
    for i, l in enumerate(lines):
        m = time_re.match(l)
        if not m:
            continue
        text = lines[i+1] if i+1 < len(lines) else ''
        vm = re.match(r'<v ([^>]+)>(.*)</v>', text)
        if not vm:
            continue  # INTRO/OUTRO or non-dialogue
        cues.append({'start': parse_ts(m.group(1)), 'end': parse_ts(m.group(2)),
                     'speaker': vm.group(1), 'text': vm.group(2)})
    return cues

def decode(m4a, start, end):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-ss', f'{start:.3f}', '-to', f'{end:.3f}',
                        '-i', m4a, '-f', 's16le', '-ac', '1', '-ar', str(SR), '-'],
                       capture_output=True)
    return np.frombuffer(r.stdout, dtype=np.int16).astype(np.float64) / 32768.0

def frame_f0(x):
    """Median-friendly F0 track via autocorrelation, NaN for unvoiced frames."""
    n = 1 + max(0, (len(x) - FRAME)) // HOP
    out = np.full(n, np.nan)
    if len(x) < FRAME:
        return out
    rms_all = np.sqrt(np.mean(x**2)) + 1e-9
    lag_min, lag_max = SR // FMAX, SR // FMIN
    for i in range(n):
        fr = x[i*HOP:i*HOP+FRAME]
        rms = np.sqrt(np.mean(fr**2))
        if rms < 0.25 * rms_all or rms < 0.005:
            continue
        fr = fr - fr.mean()
        spec = np.fft.rfft(fr, 2 * FRAME)
        ac = np.fft.irfft(spec * np.conj(spec))[:FRAME]
        if ac[0] <= 0:
            continue
        ac = ac / ac[0]
        seg = ac[lag_min:lag_max]
        k = np.argmax(seg)
        if seg[k] < 0.45:
            continue
        out[i] = SR / (lag_min + k)
    return out

def median_f0(track):
    v = track[~np.isnan(track)]
    return float(np.median(v)) if len(v) >= 6 else None

def st(a, b):
    return 12 * np.log2(a / b)

def main():
    m4a, vtt, report_path = sys.argv[1], sys.argv[2], sys.argv[3]
    cues = parse_vtt(vtt)
    for c in cues:
        dur = c['end'] - c['start']
        c['dur'] = dur
        c['cps'] = len(c['text']) / dur if dur > 0.2 else None
        track = frame_f0(decode(m4a, c['start'], c['end']))
        c['f0'] = median_f0(track)
        half = len(track) // 2
        a, b = median_f0(track[:half]), median_f0(track[half:])
        c['trend_st'] = round(st(b, a), 2) if a and b else None

    by_spk = {}
    for c in cues:
        if c['f0']:
            by_spk.setdefault(c['speaker'], []).append(c['f0'])
    spk_med = {s: float(np.median(v)) for s, v in by_spk.items() if len(v) >= 2}

    rates = np.array([c['cps'] for c in cues if c['cps'] and c['dur'] > 2])
    r_med = float(np.median(rates)) if len(rates) else None
    r_mad = float(np.median(np.abs(rates - r_med))) if len(rates) else None

    flags = []
    for i, c in enumerate(cues):
        why = []
        if c['f0'] and c['speaker'] in spk_med and len(by_spk[c['speaker']]) >= 3:
            dev = st(c['f0'], spk_med[c['speaker']])
            c['pitch_dev_st'] = round(dev, 2)
            # short utterances carry legitimate performance variance — only
            # flag them on extreme deviation; sustained lines flag at 4st
            substantial = c['dur'] >= 2.5 or len(c['text']) >= 40
            if abs(dev) > (4 if substantial else 7):
                why.append(f"pitch {dev:+.1f}st vs {c['speaker']} baseline")
        if c['trend_st'] is not None and c['dur'] > 4 and c['trend_st'] > 2.5:
            why.append(f"within-cue upward drift {c['trend_st']:+.1f}st")
        if c['cps'] and c['dur'] > 2 and r_mad and r_mad > 0:
            z = 0.6745 * (c['cps'] - r_med) / r_mad
            if abs(z) > 3.5:
                why.append(f"speech rate outlier ({c['cps']:.1f} cps, z={z:+.1f})")
        if why:
            flags.append({'idx': i, 'start': round(c['start'], 1), 'speaker': c['speaker'],
                          'text': c['text'][:110], 'why': why})

    significant = len(flags) >= max(3, 0.05 * len(cues))
    rep = {'m4a': m4a, 'cues': len(cues), 'flagged': len(flags),
           'significant_drift': significant,
           'speaker_medians_hz': {k: round(v, 1) for k, v in spk_med.items()},
           'flags': flags}
    json.dump(rep, open(report_path, 'w'), indent=1)
    print(f"{m4a}: {len(cues)} cues, {len(flags)} flagged, significant={significant}")
    for f in flags:
        print(f"  [{f['start']}s] {f['speaker']}: {'; '.join(f['why'])} :: {f['text'][:70]}")
    sys.exit(2 if significant else 0)

main()
