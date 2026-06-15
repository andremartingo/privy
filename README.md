# Privy

## Local Parakeet v3 Model

Privy uses FluidAudio's Parakeet TDT v3 Core ML model for local transcription.
The model files are intentionally not committed because they are large. They are
ignored at `privy/ModelAssets/`.

To download the model into the path expected by the app:

```sh
mkdir -p privy/ModelAssets/parakeet-tdt-0.6b-v3

python3 - <<'PY'
import json
import pathlib
import urllib.request

repo = "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml"
api = f"{repo.replace('https://huggingface.co/', 'https://huggingface.co/api/models/')}"
target = pathlib.Path("privy/ModelAssets/parakeet-tdt-0.6b-v3")
prefixes = (
    "Preprocessor.mlmodelc/",
    "Encoder.mlmodelc/",
    "Decoder.mlmodelc/",
    "JointDecisionv3.mlmodelc/",
)
standalone = {"config.json", "parakeet_vocab.json"}

with urllib.request.urlopen(api) as response:
    files = [
        item["rfilename"]
        for item in json.load(response)["siblings"]
        if item["rfilename"].startswith(prefixes) or item["rfilename"] in standalone
    ]

for name in files:
    destination = target / name
    if destination.exists():
        print(f"exists {name}")
        continue

    destination.parent.mkdir(parents=True, exist_ok=True)
    url = f"{repo}/resolve/main/{name}"
    print(f"download {name}")
    urllib.request.urlretrieve(url, destination)
PY
```

Expected result:

```sh
du -sh privy/ModelAssets/parakeet-tdt-0.6b-v3
# About 469M
```

The app also falls back to FluidAudio's model cache/download path when bundled
model assets are not present.
