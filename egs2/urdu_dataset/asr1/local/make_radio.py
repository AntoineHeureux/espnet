#!/usr/bin/env python3
"""local/make_radio.py <src_dir> <dst_dir> : dossier Kaldi dégradé (wav.scp en pipes ffmpeg + segments)."""
import random, shlex, subprocess, sys
from pathlib import Path

SEED, FRAC, PFX = 1234, 0.3, "radio"   # FRAC = part des ENREGISTREMENTS dégradés

# ---- Chaînes (nom, filtre ffmpeg, options codec, extension, encodeur requis) ----
def chain_mp3(rng):      # webradio : bande réduite + MP3 bas débit
    lp = rng.randint(3500, 7900)      # < Nyquist (8000) pour de l'audio 16 kHz
    br = rng.randint(24, 96)
    return ("mp3", f"highpass=f=100,lowpass=f={lp}",
            ["-c:a", "libmp3lame", "-b:a", f"{br}k"], "mp3", "libmp3lame")

def chain_phone(rng):    # téléphone / AM : 300-3400 Hz, 8 kHz, G.711 µ-law
    return ("phone", "highpass=f=300,lowpass=f=3400",
            ["-ar", "8000", "-c:a", "pcm_mulaw"], "wav", None)

def chain_aac(rng):      # DAB+ / streaming : compresseur + limiteur + AAC
    thr = rng.randint(-26, -16)
    ratio = rng.randint(3, 8)
    br = rng.randint(32, 80)
    return ("aac", f"acompressor=threshold={thr}dB:ratio={ratio},alimiter=limit=0.9",
            ["-c:a", "aac", "-b:a", f"{br}k"], "m4a", "aac")

def chain_opus(rng):     # voix bas débit
    hp = rng.randint(80, 200)
    br = rng.randint(12, 32)
    return ("opus", f"highpass=f={hp}",
            ["-c:a", "libopus", "-application", "voip", "-b:a", f"{br}k"],
            "opus", "libopus")

CHAINS = {"mp3": chain_mp3, "phone": chain_phone, "aac": chain_aac, "opus": chain_opus}

# extension -> (muxer d'écriture sur pipe, démuxer de lecture)
PIPE_FMT = {"mp3": ("mp3", "mp3"), "wav": ("wav", "wav"),
            "m4a": ("adts", "aac"), "opus": ("ogg", "ogg")}


def available_encoders():
    out = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"],
                         capture_output=True, text=True).stdout
    return {l.split()[1] for l in out.splitlines() if l.startswith(" ") and len(l.split()) > 1}


def read_kv(path):
    """Fichier Kaldi 'clé valeur...' -> dict clé -> valeur (str)."""
    return dict(l.split(maxsplit=1) for l in Path(path).read_text().splitlines() if l.strip())


def main(src, dst):
    src, dst = Path(src), Path(dst)
    dst.mkdir(parents=True, exist_ok=True)

    enc = available_encoders()
    probe = random.Random(0)
    names = sorted(n for n, f in CHAINS.items() if f(probe)[4] in (None, *enc))
    print(f"chaînes utilisées : {names}", file=sys.stderr)

    wav = read_kv(src / "wav.scp")                    # rec -> chemin audio
    text = read_kv(src / "text")                      # utt -> transcription
    u2s = read_kv(src / "utt2spk")                    # utt -> spk
    u2d = read_kv(src / "utt2dur") if (src / "utt2dur").exists() else {}
    segments = {}                                     # utt -> (rec, start, end)
    for l in (src / "segments").read_text().splitlines():
        if l.strip():
            utt, rec, s, e = l.split()
            segments[utt] = (rec, s, e)

    # Une chaîne par ENREGISTREMENT (déterministe, indépendante de l'ordre) :
    # tous les segments d'un même enregistrement partagent le même canal dégradé.
    chains = {}
    for rec in sorted({r for r, _, _ in segments.values()}):
        rng = random.Random(f"{SEED}-{rec}")
        if rng.random() > FRAC:
            continue
        chains[rec] = CHAINS[rng.choice(names)](rng)

    with open(dst/"wav.scp", "w") as fw, open(dst/"reco2chain", "w") as fc:
        for rec, (name, filt, opts, ext, _) in chains.items():
            path = wav[rec].strip()
            if path.endswith("|"):
                sys.exit(f"wav.scp en pipe non géré (rec {rec}) : fournir un chemin de fichier")
            mux, demux = PIPE_FMT[ext]
            fw.write(f"{PFX}-{rec} ffmpeg -nostdin -v error -i {shlex.quote(path)} "
                     f"-af {shlex.quote(filt)} {shlex.join(opts)} -f {mux} - | "
                     f"ffmpeg -v error -f {demux} -i - -ar 16000 -f wav - |\n")
            fc.write(f"{PFX}-{rec} {name} {filt} {shlex.join(opts)}\n")

    with open(dst/"segments", "w") as fs, open(dst/"text", "w") as ft, \
         open(dst/"utt2spk", "w") as fu, open(dst/"utt2dur", "w") as fd:
        for utt in sorted(segments):
            rec, s, e = segments[utt]
            if rec not in chains:
                continue
            new = f"{PFX}-{utt}"
            fs.write(f"{new} {PFX}-{rec} {s} {e}\n")
            ft.write(f"{new} {text[utt]}\n")
            fu.write(f"{new} {PFX}-{u2s[utt]}\n")
            if utt in u2d:
                fd.write(f"{new} {u2d[utt]}\n")
    if not u2d:
        (dst / "utt2dur").unlink()


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])