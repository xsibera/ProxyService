"""Synthesised hit sounds: fist impacts and sharp, bloody blade hits, each with variations.

  python3 generate_hits.py            writes wav/ (48 kHz 24-bit masters), ogg/ (for uploading),
                                      preview.ogg (every sound in turn, to audition) and HitSounds.rbxmx
                                      (the HitSounds ModuleScript, to insert into a game)

Every sound is built the way a Foley/sound-design impact is: several short layers, each shaped and
filtered on its own, then summed, put in a small room, gently saturated and levelled. Each variation
draws its own numbers (seeded, so a rebuild gives the same files) from ranges that keep it the same
kind of hit, so playing them in turn never repeats.

Fist (FistHit_1-8, light to medium; FistHeavy_1-4, big hits):
  snap     the skin slap: a few milliseconds of bright noise
  smack    the meat of it: band-passed noise in two or three quick contacts (knuckles, then palm)
  thump    the body resonating: a sine falling fast in pitch, saturated
  knuckle  a tick of bone, quiet
  cloth    a brush of clothing
  heavy    adds a sub-bass boom, a crunch (bone and cartilage: a crackle of clicks) and a bigger room

Bloody (BloodySlash_1-6, cuts; BloodyStab_1-4, stabs and gory hits):
  edge     the blade meeting flesh: a sharp, bright tick with a faint metallic ring
  slice    the cut opening: noise through a band-pass sweeping down, torn by a fibrous crackle
  splat    the wet hit: a low-mid squelch, wobbling
  drops    the blood: grains of tiny rising-pitch bubbles and splashes, thinning out
  thud     the body taking it
  (a stab has a short slice, a heavier thud and squelch, and a sucking pull-out)
"""

import math
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 48000


# --------------------------------------------------------------------------- building blocks
def seconds(n):
    return int(round(n * SR))


def env(n, attack, decay, hold=0.0, start=0):
    """An envelope: a linear rise over `attack` s, held `hold` s, then an exponential decay with time
    constant `decay` s, starting `start` samples in."""
    t = (np.arange(n) - start) / SR
    out = np.where(t < 0, 0.0, np.where(t < attack, t / max(attack, 1e-6), 1.0))
    after = t - attack - hold
    return out * np.where(after > 0, np.exp(-np.maximum(after, 0) / decay), 1.0)


def biquad(kind, f0, q=0.707, gain_db=0.0):
    """RBJ cookbook biquad coefficients (b, a), normalised."""
    w = 2 * math.pi * min(f0, SR * 0.45) / SR
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2 * q)
    big_a = 10 ** (gain_db / 40)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * big_a, -2 * cw, 1 - alpha * big_a]
        a = [1 + alpha / big_a, -2 * cw, 1 - alpha / big_a]
    elif kind == "lowshelf":
        sq = 2 * math.sqrt(big_a) * alpha
        b = [big_a * ((big_a + 1) - (big_a - 1) * cw + sq), 2 * big_a * ((big_a - 1) - (big_a + 1) * cw),
             big_a * ((big_a + 1) - (big_a - 1) * cw - sq)]
        a = [(big_a + 1) + (big_a - 1) * cw + sq, -2 * ((big_a - 1) + (big_a + 1) * cw),
             (big_a + 1) + (big_a - 1) * cw - sq]
    else:
        raise ValueError(kind)
    return np.array(b) / a[0], np.array(a) / a[0]


def run(x, b, a):
    """Apply a biquad (direct form II transposed), causal like a real filter (no pre-ringing)."""
    y = np.empty_like(x)
    b0, b1, b2 = b
    _, a1, a2 = a
    z1 = z2 = 0.0
    for i, v in enumerate(x):
        out = b0 * v + z1
        z1 = b1 * v - a1 * out + z2
        z2 = b2 * v - a2 * out
        y[i] = out
    return y


def filt(x, kind, f0, q=0.707, gain_db=0.0, order=1):
    for _ in range(order):
        x = run(x, *biquad(kind, f0, q, gain_db))
    return x


def sweep_bp(x, f_start, f_end, q, length, start=0):
    """A band-pass whose centre glides from f_start to f_end (exponentially) over `length` s, from
    `start` samples in."""
    y = np.empty_like(x)
    z1 = z2 = 0.0
    block = 32
    for s in range(0, len(x), block):
        u = min(1.0, max(0.0, (s - start) / SR / length))
        b, a = biquad("bp", f_start * (f_end / f_start) ** u, q)
        b0, b1, b2 = b
        _, a1, a2 = a
        for i in range(s, min(s + block, len(x))):
            v = x[i]
            out = b0 * v + z1
            z1 = b1 * v - a1 * out + z2
            z2 = b2 * v - a2 * out
            y[i] = out
    return y


def falling_sine(n, f_start, f_end, tau, start=0):
    """A sine whose pitch falls from f_start toward f_end with time constant tau (a drum's thump)."""
    t = np.maximum(np.arange(n) - start, 0) / SR
    f = f_end + (f_start - f_end) * np.exp(-t / tau)
    phase = 2 * math.pi * np.cumsum(f) / SR
    return np.where(np.arange(n) >= start, np.sin(phase), 0.0)


def wobble(rng, n, rate, depth):
    """An irregular wobble (smoothed noise around 1): wet things never pulse evenly."""
    m = filt(rng.standard_normal(n), "lp", rate, 0.707, order=2)
    return 1 + depth * m / max(np.max(np.abs(m)), 1e-9)


def norm(x):
    p = np.max(np.abs(x))
    return x / p if p > 0 else x


def room(rng, rt, damp, size=1.0):
    """A small room's impulse response: a few early reflections, then a decaying, darkening tail."""
    n = seconds(rt * 1.3)
    ir = np.zeros(n)
    ir[0] = 1.0
    for _ in range(6):
        k = int(rng.uniform(0.004, 0.025) * size * SR)
        ir[k] += rng.uniform(-0.45, 0.45)
    tail = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / (rt / 6.9))
    tail = filt(tail, "lp", damp)
    ir += 0.35 * tail * (np.arange(n) > int(0.012 * SR))
    return ir


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]
    return y[: len(x)]


def master(x, drive=1.4, peak_db=-1.0, fade=0.012):
    """The bus: rumble cut, the fizz above 15 kHz rounded off, soft saturation (glue and weight),
    levelled to the peak and faded out."""
    x = filt(x, "hp", 32, 0.707, order=2)
    x = filt(x, "lp", 15000, 0.707)
    x = np.tanh(drive * norm(x)) / math.tanh(drive)
    f = seconds(fade)
    x[-f:] *= np.linspace(1, 0, f) ** 2
    return norm(x) * 10 ** (peak_db / 20)


def trim(x, floor_db=-60):
    """Cut the silent tail (below floor_db of the peak), keeping a short fade."""
    level = np.abs(x) / max(np.max(np.abs(x)), 1e-9)
    loud = np.nonzero(level > 10 ** (floor_db / 20))[0]
    end = min(len(x), (loud[-1] if len(loud) else len(x)) + seconds(0.02))
    return x[:end]


# --------------------------------------------------------------------------- fists
def punch(rng, weight):
    """A fist hit. weight 0 is a quick jab, 1 a solid cross."""
    n = seconds(0.55)
    x = np.zeros(n)
    noise = lambda: rng.standard_normal(n)  # noqa: E731
    # snap: the skin slap
    snap = filt(noise(), "hp", rng.uniform(1400, 2200), 0.7, order=2)
    snap = filt(snap, "peak", rng.uniform(3000, 5200), 1.2, 6)
    x += 0.9 * snap * env(n, 0.0003, rng.uniform(0.0022, 0.0038))
    # smack: the meat, in two or three quick contacts
    centre = rng.uniform(650, 1100) * (1 - 0.25 * weight)
    smack_src = filt(noise(), "bp", centre, rng.uniform(1.2, 1.6))
    smack_src += 0.8 * filt(noise(), "bp", rng.uniform(220, 320), 1.2)
    smack_src = filt(smack_src, "lp", rng.uniform(3200, 4200), 0.707, order=2)  # the highs are the snap's
    contacts = np.zeros(n)
    at, level = 0, 1.0
    for _ in range(rng.integers(2, 4)):
        contacts += level * env(n, 0.0008, rng.uniform(0.018, 0.032) * (1 + 0.4 * weight), start=at)
        at += seconds(rng.uniform(0.003, 0.009))
        level *= rng.uniform(0.45, 0.7)
    x += 2.6 * smack_src * contacts
    # thump: the body resonating
    thump = falling_sine(n, rng.uniform(150, 200), rng.uniform(55, 75) - 10 * weight, rng.uniform(0.02, 0.03))
    thump = np.tanh(2.2 * thump) * env(n, 0.001, rng.uniform(0.035, 0.05) * (1 + 0.5 * weight))
    x += (0.6 + 0.25 * weight) * thump
    # knuckle: a tick of bone
    for _ in range(rng.integers(1, 3)):
        k = seconds(rng.uniform(0.0, 0.006))
        click = filt(noise(), "bp", rng.uniform(2200, 4200), 3.0) * env(n, 0.0001, 0.0009, start=k)
        x += 0.45 * click
    # cloth: a brush of clothing
    cloth = filt(noise(), "hp", rng.uniform(3500, 5500), 0.7, order=2)
    x += 0.12 * cloth * env(n, 0.002, rng.uniform(0.015, 0.03))
    wet = room(rng, rng.uniform(0.12, 0.2), rng.uniform(3000, 5000))
    x = x + rng.uniform(0.05, 0.09) * convolve(x, wet)
    return trim(master(x, drive=1.1 + 0.3 * weight))


def heavy_punch(rng):
    """A big hit: a punch with a sub boom, a crunch and a bigger room."""
    n = seconds(0.9)
    x = np.zeros(n)
    base = punch(rng, 1.0)
    x[: len(base)] += base
    noise = lambda: rng.standard_normal(n)  # noqa: E731
    # sub boom
    boom = falling_sine(n, rng.uniform(95, 120), rng.uniform(36, 46), rng.uniform(0.04, 0.06))
    x += 0.32 * np.tanh(1.8 * boom) * env(n, 0.002, rng.uniform(0.065, 0.085))
    body = filt(noise(), "lp", rng.uniform(140, 190), 0.9, order=2)  # the rumble round the boom
    x += 0.5 * norm(body) * env(n, 0.003, rng.uniform(0.05, 0.07))
    # crunch: bone and cartilage giving, a crackle of clicks over a few tens of milliseconds
    crunch = np.zeros(n)
    t = seconds(rng.uniform(0.002, 0.006))
    for _ in range(rng.integers(10, 18)):
        crunch[t] += rng.uniform(0.3, 1.0) * rng.choice([-1, 1])
        t += seconds(rng.uniform(0.0015, 0.005))
    crunch = filt(crunch, "bp", rng.uniform(1600, 2800), 1.4)
    crunch = filt(crunch, "peak", rng.uniform(4000, 6000), 2.0, 4)
    x += 0.75 * norm(crunch) * env(n, 0.0005, 0.035)
    # a second, harder slap on top (the weight behind it)
    slap = filt(filt(noise(), "bp", rng.uniform(900, 1400), 0.9), "peak", rng.uniform(2500, 3500), 1.5, 5)
    x += 0.6 * slap * env(n, 0.0005, rng.uniform(0.02, 0.03))
    # a low-mid push of air
    air = filt(noise(), "lp", 900, 0.7, order=2) * env(n, 0.004, 0.06)
    x += 0.25 * air
    wet = room(rng, rng.uniform(0.25, 0.35), rng.uniform(2800, 4000), size=1.6)
    x = x + rng.uniform(0.08, 0.12) * convolve(x, wet)
    return trim(master(x, drive=1.5))


# --------------------------------------------------------------------------- blades and blood
def drops(rng, n, start, length, count, low=450, high=2600):
    """Blood: grains of tiny bubbles (damped sines rising in pitch) and splashes, thinning out."""
    out = np.zeros(n)
    t_all = np.arange(n) / SR
    for _ in range(count):
        at = start + seconds(length * rng.random() ** 1.8)  # bunched at the start, thinning out
        if at >= n - 10:
            continue
        f0 = math.exp(rng.uniform(math.log(low), math.log(high)))
        decay = rng.uniform(0.004, 0.014)
        t = np.maximum(t_all - at / SR, 0)
        f = f0 * (1 + rng.uniform(0.04, 0.12) * t / decay)  # a bubble rises a little as it closes
        phase = 2 * math.pi * np.cumsum(f) / SR
        grain = np.sin(phase - phase[at]) * np.exp(-t / decay) * (1 - np.exp(-t / 0.0003)) * (t_all >= at / SR)
        out += rng.uniform(0.2, 1.0) * grain
        if rng.random() < 0.35:  # a splash with it
            splash = filt(filt(rng.standard_normal(n), "bp", rng.uniform(1200, 3500), 1.5), "lp", 5000)
            out += rng.uniform(0.15, 0.4) * splash * env(n, 0.002, rng.uniform(0.003, 0.008), start=at)
    return out


def fibres(rng, n, start, length, rate):
    """A tearing crackle: random gated pulses, denser at first."""
    out = np.ones(n)
    t = start
    end = start + seconds(length)
    while t < end:
        width = seconds(rng.uniform(0.0006, 0.003))
        out[t:t + width] += rng.uniform(0.4, 1.4)
        t += seconds(rng.exponential(1 / rate))
    return out


def edge(rng, n):
    """The blade meeting flesh: a sharp bright tick with a faint metallic ring."""
    tick = filt(rng.standard_normal(n), "hp", rng.uniform(2800, 3800), 0.7, order=2)
    tick = filt(tick, "peak", rng.uniform(6000, 8500), 2.0, 8)
    out = tick * env(n, 0.0002, rng.uniform(0.0015, 0.003))
    t = np.arange(n) / SR
    base = rng.uniform(2900, 3600)
    for ratio, amp in ((1.0, 1.0), (1.73, 0.55), (2.61, 0.3)):
        out += 0.04 * amp * np.sin(2 * math.pi * base * ratio * t + rng.uniform(0, 6.28)) * np.exp(
            -t / rng.uniform(0.02, 0.04))
    return out


def cut(rng):
    """A sharp, bloody cut."""
    n = seconds(0.7)
    x = np.zeros(n)
    noise = lambda: rng.standard_normal(n)  # noqa: E731
    x += 0.7 * edge(rng, n)
    # slice: the cut opening, a band-pass sweeping down, torn by fibres
    length = rng.uniform(0.07, 0.12)
    slice_ = sweep_bp(noise(), rng.uniform(4500, 6500), rng.uniform(1100, 1700), rng.uniform(1.6, 2.4), length)
    slice_ *= fibres(rng, n, 0, length, rng.uniform(250, 450))
    x += 0.75 * slice_ * env(n, 0.0015, rng.uniform(0.03, 0.05), hold=length * 0.6)
    # splat: the wet hit, a low-mid squelch wobbling
    splat = filt(noise(), "bp", rng.uniform(380, 650), 1.1) + 0.6 * filt(noise(), "bp", rng.uniform(900, 1400), 1.6)
    start = seconds(rng.uniform(0.004, 0.012))
    x += 1.5 * splat * wobble(rng, n, rng.uniform(25, 45), 0.6) * env(n, 0.002, rng.uniform(0.045, 0.075), start=start)
    # drops: the blood
    x += 0.5 * drops(rng, n, seconds(0.01), rng.uniform(0.18, 0.3), rng.integers(16, 28))
    # thud: the body taking it
    thud = falling_sine(n, rng.uniform(120, 150), rng.uniform(58, 70), 0.025)
    x += 0.45 * np.tanh(2 * thud) * env(n, 0.001, rng.uniform(0.05, 0.07))
    wet = room(rng, rng.uniform(0.16, 0.24), rng.uniform(4500, 7000))
    x = x + rng.uniform(0.08, 0.13) * convolve(x, wet)
    return trim(master(x, drive=1.25))


def stab(rng):
    """A stab or a gory, heavy blade hit: a short slice, a heavy thud and squelch, and the pull-out."""
    n = seconds(0.85)
    x = np.zeros(n)
    noise = lambda: rng.standard_normal(n)  # noqa: E731
    x += 0.55 * edge(rng, n)
    length = rng.uniform(0.035, 0.06)
    slice_ = sweep_bp(noise(), rng.uniform(3500, 5000), rng.uniform(900, 1300), 2.0, length)
    slice_ *= fibres(rng, n, 0, length, 500)
    x += 0.7 * slice_ * env(n, 0.001, 0.025, hold=length * 0.5)
    # the squelch: heavier and lower, two pulses (in, and the body giving)
    squelch = filt(noise(), "bp", rng.uniform(260, 420), 1.0) + 0.5 * filt(noise(), "bp", rng.uniform(700, 1000), 1.4)
    x += 1.5 * squelch * wobble(rng, n, rng.uniform(20, 35), 0.7) * (env(n, 0.002, 0.06, start=seconds(0.003))
                                   + 0.55 * env(n, 0.004, 0.05, start=seconds(rng.uniform(0.05, 0.08))))
    thud = falling_sine(n, rng.uniform(110, 130), rng.uniform(45, 55), 0.035)
    x += 0.5 * np.tanh(2.4 * thud) * env(n, 0.001, rng.uniform(0.06, 0.085))
    x += 0.35 * drops(rng, n, seconds(0.015), rng.uniform(0.25, 0.4), rng.integers(18, 30), 380, 2200)
    # the pull-out: a short sucking sweep upward, a moment later
    at = seconds(rng.uniform(0.2, 0.28))
    pull = sweep_bp(noise(), rng.uniform(500, 700), rng.uniform(1600, 2400), 2.2, 0.07, start=at)
    pull_env = env(n, 0.025, 0.025, start=at)
    x += 0.35 * pull * pull_env
    x += 0.2 * drops(rng, n, at, 0.15, rng.integers(6, 12), 600, 2400)
    wet = room(rng, rng.uniform(0.2, 0.3), rng.uniform(4000, 6000))
    x = x + rng.uniform(0.1, 0.14) * convolve(x, wet)
    return trim(master(x, drive=1.5))


# --------------------------------------------------------------------------- the set
SET = (
    [("FistHit_%d" % (i + 1), lambda rng, w=i / 7: punch(rng, 0.15 + 0.6 * w)) for i in range(8)]
    + [("FistHeavy_%d" % (i + 1), heavy_punch) for i in range(4)]
    + [("BloodySlash_%d" % (i + 1), cut) for i in range(6)]
    + [("BloodyStab_%d" % (i + 1), stab) for i in range(4)]
)


def write_wav(path, x):
    pcm = np.clip(np.round(x * (2 ** 23 - 1)), -(2 ** 23), 2 ** 23 - 1).astype("<i4")
    raw = b"".join(int(v).to_bytes(4, "little", signed=True)[:3] for v in pcm)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(3)
        w.setframerate(SR)
        w.writeframes(raw)


def to_ogg(wav, ogg):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "8", ogg], check=True)


def build():
    os.makedirs(os.path.join(HERE, "wav"), exist_ok=True)
    os.makedirs(os.path.join(HERE, "ogg"), exist_ok=True)
    sounds = {}
    for i, (name, make) in enumerate(SET):
        rng = np.random.default_rng(1000 + i)
        x = make(rng)
        sounds[name] = x
        wav = os.path.join(HERE, "wav", name + ".wav")
        write_wav(wav, x)
        to_ogg(wav, os.path.join(HERE, "ogg", name + ".ogg"))
        rms = 20 * math.log10(math.sqrt(float(np.mean(x ** 2))) + 1e-12)
        peak = 20 * math.log10(np.max(np.abs(x)))
        print("%-14s %.2fs  peak %.1f dBFS  rms %.1f dBFS" % (name, len(x) / SR, peak, rms))
    # preview: every sound in turn, a beat apart
    gap = np.zeros(seconds(0.45))
    preview = np.concatenate([np.concatenate([sounds[name], gap]) for name, _ in SET])
    wav = os.path.join(HERE, "preview.wav")
    write_wav(wav, preview)
    to_ogg(wav, os.path.join(HERE, "preview.ogg"))
    os.remove(wav)
    sys.path.insert(0, os.path.join(HERE, "..", "..", "Abilities", "Shared"))
    import rbxbuild

    module = rbxbuild.module("HitSounds", os.path.join(HERE, "HitSounds.luau"))
    rbxbuild.write([module], os.path.join(HERE, "HitSounds.rbxmx"))
    return sounds


if __name__ == "__main__":
    build()
