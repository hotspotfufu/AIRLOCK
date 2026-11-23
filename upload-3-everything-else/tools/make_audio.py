"""DEV TOOL. Synthesises the placeholder sound effects (no recordings needed).
Run:  python3 tools/make_audio.py   -> writes assets/audio/sfx/*.wav and ambience/hum.wav
Replace any file with a real recording of the same name and the game uses it."""
import numpy as np, wave, os
SR = 22050
rng = np.random.default_rng(7)
def save(path, x):
    x = np.clip(x / max(1e-9, np.abs(x).max()) * 0.85, -1, 1)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
def t(sec): return np.arange(int(SR * sec)) / SR
def noise(sec): return rng.standard_normal(int(SR * sec))
def lowpass(x, k):
    y = np.zeros_like(x); a = 0.0
    for i, v in enumerate(x):
        a += k * (v - a); y[i] = a
    return y
def env(n, attack, decay):
    e = np.exp(-np.arange(n) / (SR * decay)); a = int(SR * attack)
    if a > 0: e[:a] *= np.linspace(0, 1, a)
    return e
S = 'assets/audio/sfx/'
# metal footstep: low thud + short metallic ring
x = t(0.22); n = len(x)
save(S + 'step.wav', lowpass(noise(0.22), 0.12) * env(n, 0.002, 0.035) * 1.5 + np.sin(2*np.pi*410*x) * env(n, 0.001, 0.05) * 0.25 + np.sin(2*np.pi*95*x) * env(n, 0.002, 0.06))
x = t(0.05); save(S + 'click.wav', noise(0.05) * env(len(x), 0.0005, 0.006) + np.sin(2*np.pi*2100*x) * env(len(x), 0.0005, 0.01))
# door: servo whirr rising then clunk
x = t(1.4); n = len(x)
whirr = np.sin(2*np.pi*np.cumsum(90 + 60*np.minimum(x/1.1, 1)) / SR) * 0.5 + lowpass(noise(1.4), 0.2) * 0.4
whirr *= np.minimum(1, x/0.08) * (x < 1.15)
clunk = np.zeros(n); k = int(1.15*SR); m = n - k
clunk[k:] = (np.sin(2*np.pi*70*t(m/SR)[:m]) + lowpass(noise(m/SR)[:m], 0.3)) * env(m, 0.001, 0.05)
save(S + 'door.wav', whirr + clunk * 1.6)
x = t(1.2); save(S + 'alarm.wav', np.sign(np.sin(2*np.pi*620*x)) * 0.3 * (np.sin(2*np.pi*2.5*x) > 0) * np.sin(2*np.pi*620*x)**2 + np.sin(2*np.pi*620*x) * (np.sin(2*np.pi*2.5*x) > 0) * 0.5)
x = t(0.28); save(S + 'confirm.wav', (np.sin(2*np.pi*880*x) * (x < 0.12) + np.sin(2*np.pi*1320*x) * (x >= 0.12)) * env(len(x), 0.003, 0.12))
x = t(0.25); save(S + 'deny.wav', np.sign(np.sin(2*np.pi*150*x)) * env(len(x), 0.003, 0.12))
x = t(0.6); n = len(x)
g = np.zeros(n)
for _ in range(26):
    k = int(rng.uniform(0, 0.35) * SR); f = rng.uniform(2500, 7000); m = min(n - k, int(0.12 * SR))
    g[k:k+m] += np.sin(2*np.pi*f*t(m/SR)[:m]) * env(m, 0.0005, rng.uniform(0.01, 0.04)) * rng.uniform(0.3, 1)
save(S + 'glass.wav', g + noise(0.6) * env(n, 0.0005, 0.03))
x = t(0.35); n = len(x); save(S + 'lever.wav', lowpass(noise(0.35), 0.25) * env(n, 0.001, 0.03) * 2 + np.sin(2*np.pi*130*x) * env(n, 0.001, 0.07))
x = t(2.2); save(S + 'power_up.wav', np.sin(2*np.pi*np.cumsum(40 + 180*(x/2.2)**2) / SR) * np.minimum(1, x/0.3) * np.minimum(1, (2.2-x)/0.5) + np.sin(2*np.pi*np.cumsum(80 + 360*(x/2.2)**2) / SR) * 0.3 * np.minimum(1, (2.2-x)/0.5))
x = t(1.3); save(S + 'hiss.wav', (noise(1.3) - lowpass(noise(1.3), 0.3)) * np.minimum(1, x/0.05) * np.exp(-x/0.45))
# swarm: many tiny metallic ticks, like needles on steel
x = t(2.2); n = len(x); g = np.zeros(n)
for _ in range(260):
    k = int(rng.uniform(0, 2.0) * SR); f = rng.uniform(3000, 9000); m = min(n - k, int(0.02 * SR))
    g[k:k+m] += np.sin(2*np.pi*f*t(m/SR)[:m]) * env(m, 0.0003, 0.004) * rng.uniform(0.2, 1)
save(S + 'skitter.wav', g * np.sin(np.pi * x / 2.2) ** 0.5 + np.sin(2*np.pi*55*x) * 0.25 * np.sin(np.pi*x/2.2))
x = t(0.18); save(S + 'pickup.wav', np.sin(2*np.pi*(500 + 900*x/0.18)*x) * env(len(x), 0.002, 0.08))
x = t(0.3); save(S + 'hurt.wav', lowpass(noise(0.3), 0.08) * env(len(x), 0.002, 0.08))
# helmet breathing loop (4 s: in, out)
x = t(4.0); br = lowpass(noise(4.0), 0.07) - lowpass(noise(4.0), 0.02)
shape = np.maximum(0, np.sin(2*np.pi*x/4.0)) ** 1.5 + 0.7 * np.maximum(0, -np.sin(2*np.pi*x/4.0)) ** 2
save(S + 'breath.wav', br * shape)
# station hum loop (6 s, whole number of cycles so it loops cleanly)
x = t(6.0); hum = np.sin(2*np.pi*50*x) * 0.5 + np.sin(2*np.pi*100*x) * 0.25 + np.sin(2*np.pi*150.5*x) * 0.1
rum = lowpass(noise(6.0), 0.01); rum = rum * np.minimum(1, x/0.5) * np.minimum(1, (6.0-x)/0.5)
save('assets/audio/ambience/hum.wav', hum * (0.8 + 0.2*np.sin(2*np.pi*x/6.0)) + rum * 6)
print('audio written')
