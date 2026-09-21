"""Optional room-microphone preprocessing; originals and sample positions survive."""
import os
from pathlib import Path
import tempfile
import time


def check_expiry(state):
    if state.get('audioExpiresAt') and time.time()*1000 >= state['audioExpiresAt']:
        raise ValueError('Audio-Aufbewahrungszeit abgelaufen')


def enhance(source, destination, config, state):
    os.environ.setdefault('PYTORCH_ENABLE_MPS_FALLBACK', '1')
    import numpy as np
    import soundfile as sf
    import torch
    from clearvoice.network_wrapper import network_wrapper
    from clearvoice.networks import CLS_MossFormerGAN_SE_16K
    check_expiry(state)
    signal, rate = sf.read(source, dtype='float32')
    if rate != 16000 or signal.ndim != 1:
        raise ValueError('Sprachaufbereitung benötigt Mono-Audio mit 16 kHz')
    if not len(signal) or not np.any(signal):
        output = signal
    else:
        wrapper = network_wrapper()
        wrapper.model_name = 'MossFormerGAN_SE_16K'
        wrapper.load_args_se()
        wrapper.args.checkpoint_dir = config['enhancementModel']
        wrapper.args.task = 'speech_enhancement'
        wrapper.args.network = wrapper.model_name
        model = CLS_MossFormerGAN_SE_16K(wrapper.args)
        # Upstream otherwise permits a partially loaded checkpoint without failure.
        checkpoint = torch.load(Path(config['enhancementModel'])/'last_best_checkpoint.pt',
                                map_location='cpu', weights_only=True)
        weights = checkpoint.get('model', checkpoint)
        for key, value in model.model.state_dict().items():
            candidates = [weights[k] for k in (key, key.removeprefix('module.'), 'module.'+key) if k in weights]
            if not any(value.shape == candidate.shape for candidate in candidates):
                raise ValueError('Unvollständiges Sprachaufbereitungsmodell: '+key)
        del checkpoint, weights
        output = np.asarray(model.decode_data(signal[None, :])).reshape(-1)
        if len(output) != len(signal) or not np.isfinite(output).all():
            raise ValueError('Ungültige Länge oder Werte nach Sprachaufbereitung')
    check_expiry(state)
    # Derived audio stays inside the original session and shares its deletion date.
    destination = Path(destination)
    with tempfile.NamedTemporaryFile(dir=destination.parent, suffix='.wav', delete=False) as f:
        temp = f.name
    try:
        sf.write(temp, output, rate, subtype='PCM_16')
        check_expiry(state)
        os.replace(temp, destination)
    finally:
        if os.path.exists(temp): os.unlink(temp)
