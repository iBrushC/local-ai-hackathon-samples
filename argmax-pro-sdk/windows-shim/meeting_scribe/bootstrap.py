"""
License activation, model selection, and WhisperKitPro setup.
Swift twin: native/Sources/MeetingScribe/Bootstrap.swift

Docs: https://app.argmaxinc.com/docs/guides/upgrading-to-pro-sdk
      https://app.argmaxinc.com/docs/examples/custom-vocabulary
"""

import os

from argmax_shim.argmax import (
    ArgmaxConfig,
    ArgmaxSDK,
    CustomVocabularyConfig,
    WhisperKitPro,
    WhisperKitProConfig,
)


class Models:
    # Whisper large-v3 turbo: multilingual and accurate, but it doesn't support custom vocabulary.
    # This is also the most portable backend on native Windows (faster-whisper).
    DEFAULT_ASR = "large-v3-v20240930_626MB"
    # Parakeet v3: 25 languages, supports custom vocabulary. Used when the user passes a vocabulary.
    # Shim: needs the [parakeet] extra (NeMo). Use WSL2 on Windows.
    VOCABULARY_ASR = "parakeet-v3_494MB"

    @staticmethod
    def is_whisper(name: str) -> bool:
        return name.startswith(("large-", "tiny", "base", "small"))


def activate_sdk(api_key: str | None) -> None:
    """Swift: await ArgmaxSDK.with(ArgmaxConfig(apiKey: key))

    The real SDK validates the key online and caches a per-device license.
    The shim accepts any key, so a placeholder works on Windows.
    """
    key = api_key or os.environ.get("ARGMAX_API_KEY") or "ax_dev_placeholder"
    ArgmaxSDK.with_(ArgmaxConfig(api_key=key))


def make_whisper_kit_pro(model: str, vocabulary: list[str]) -> WhisperKitPro:
    """Creates WhisperKitPro and enables custom vocabulary if any terms were given."""
    if vocabulary and Models.is_whisper(model):
        # Custom vocabulary is disabled for Whisper models in the Pro SDK (and in the shim).
        print(f"Custom vocabulary needs a non-Whisper model; switching {model} -> {Models.VOCABULARY_ASR}")
        model = Models.VOCABULARY_ASR

    print(f"Loading {model} (first run downloads it)...")
    if not vocabulary:
        config = WhisperKitProConfig(model=model)
    else:
        # Swift: WhisperKitProConfig(model:, customVocabularyConfig: .init(words: vocabulary))
        # Change terms at runtime with whisper_kit_pro.set_custom_vocabulary([...]).
        # Shim: fuzzy text correction on Parakeet output. The real SDK uses audio keyword spotting.
        config = WhisperKitProConfig(model=model, custom_vocabulary_config=CustomVocabularyConfig(words=vocabulary))
    whisper_kit_pro = WhisperKitPro(config)

    if vocabulary:
        print(f"Custom vocabulary ({len(vocabulary)} terms): {whisper_kit_pro.custom_vocabulary_model_state.value}")
    return whisper_kit_pro
