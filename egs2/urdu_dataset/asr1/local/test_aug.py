import torch, torchaudio
from espnet2.layers.augmentation import _chain_aac

wav, sr = torchaudio.load("/workspace/data/ai4bharat/wavs/SPEAKER_0001-test-0001397.wav")
x = wav.mean(0)[: 5 * 16000]
y = _chain_aac(x, 16000)
n = len(x)
# corrélation croisée par FFT sur la fenêtre de décalage plausible (0 à 2048)
L = n + len(y)
X, Y = torch.fft.rfft(x, L), torch.fft.rfft(y, L)
cc = torch.fft.irfft(Y * X.conj(), L)[:2048]
print("décalage estimé (échantillons) :", cc.argmax().item())