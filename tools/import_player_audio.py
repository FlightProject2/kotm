"""Copy the 22 user-selected WAVs unchanged; generate auditable source metadata."""
import hashlib
import json
from pathlib import Path
import shutil
import wave

FILES = {
    "PLAYER-SHOT HURT.wav": "hurt.wav",
    "PUNCH 1.wav": "punch_1.wav", "PUNCH 2.wav": "punch_2.wav",
    "RIGHT FOOTSTEP NORMAL FLOOR.wav": "step_hard_right.wav",
    "TOUCHING METAL FENCE 2.wav": "fence_2.wav", "TOUCHING METAL FENCE.wav": "fence_1.wav",
    "WALKING ON METAL.wav": "step_metal.wav", "WALKING ON STICK.wav": "step_wood.wav",
    "WALKING ON WATER 1.wav": "step_water_1.wav", "WALKING ON WATER 2.wav": "step_water_2.wav",
    "WATER 3 - DEEPER.wav": "step_water_deep.wav",
    "DEEP - GAS ATTACK - COUGHING.wav": "cough_heavy.wav",
    "door locked.wav": "door_locked.wav",
    "DYING 2.wav": "death_2.wav", "DYING 3.wav": "death_3.wav", "DYING.wav": "death_1.wav",
    "GAS ATTACK - COUGH.wav": "cough.wav", "JUMPING.wav": "jump.wav",
    "LEFT FOOTSTEP GRASS.wav": "step_grass.wav", "LIGHT LEFT FOOTSTEP.wav": "step_light_left.wav",
    "OUT OF STAMINA.wav": "exertion_1.wav", "OUT OF STANIMA 2.wav": "exertion_2.wav",
}

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    dest = Path(__file__).resolve().parents[1] / "assets/audio/player"
    dest.mkdir(parents=True, exist_ok=True)
    entries = []
    for source_name, target_name in FILES.items():
        src, out = args.source / source_name, dest / target_name
        shutil.copyfile(src, out)
        digest = hashlib.sha256(src.read_bytes()).hexdigest()
        assert digest == hashlib.sha256(out.read_bytes()).hexdigest()
        with wave.open(str(out), "rb") as wav:
            entry = dict(file=target_name, source_basename=source_name, sha256=digest,
                         bytes=out.stat().st_size, frames=wav.getnframes(), sample_rate=wav.getframerate(),
                         channels=wav.getnchannels(), bits_per_sample=wav.getsampwidth()*8,
                         duration_seconds=round(wav.getnframes()/wav.getframerate(), 6))
        entries.append(entry)
    (dest / "manifest.json").write_text(json.dumps(dict(
        provenance="User-provided player effects; original filenames retained below. Not CC0.",
        processing="Byte-for-byte copies; runtime gain/pitch and Godot import do not alter source WAV files.",
        files=entries), indent=2)+"\n", encoding="utf-8")
    print(json.dumps(dict(files=len(entries), total_bytes=sum(e['bytes'] for e in entries), files_metadata=entries), indent=2))

if __name__ == "__main__":
    main()
