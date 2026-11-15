# Third-party components

This installer downloads every component from its original publisher and redistributes nothing.
Each component keeps its own licence. **"Not restricted by OpenLayer" does not mean "no licence
terms"**: read each model page before commercial use.

## Software

| Component | Licence | Source |
| --- | --- | --- |
| ComfyUI | GPL-3.0 | https://github.com/Comfy-Org/ComfyUI |
| OpenLayer (Photoshop plugin and model manifest) | MIT | https://github.com/MehranMarxian/OpenLayer |
| 7-Zip (installed with winget only if missing) | LGPL-2.1 + unRAR restriction | https://7-zip.org |
| Adobe Creative Cloud desktop app (only with `-InstallCreativeCloud`) | Adobe terms | https://www.adobe.com/creativecloud/desktop-app.html |

## ComfyUI custom node packages

Licences vary; check each repository.

| Package | Repository |
| --- | --- |
| comfyui_controlnet_aux | https://github.com/Fannovel16/comfyui_controlnet_aux |
| ComfyUI_IPAdapter_plus | https://github.com/cubiq/ComfyUI_IPAdapter_plus |
| comfyui-art-venture | https://github.com/sipherxyz/comfyui-art-venture |
| ComfyUI-Florence2 | https://github.com/kijai/ComfyUI-Florence2 |
| ComfyUI-GGUF | https://github.com/city96/ComfyUI-GGUF |
| comfyui-inpaint-cropandstitch | https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch |
| ComfyUI-KJNodes | https://github.com/kijai/ComfyUI-KJNodes |

## Models (from manifest/openlayer-requirements.json, OpenLayer 0.41.0)

| File | Folder | Size | Licence gate | Source |
| --- | --- | --- | --- | --- |
| `birefnet.safetensors` | `models/background_removal` | 444 MB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/BiRefNet) |
| `flux1-dev-fp8.safetensors` | `models/checkpoints` | 17.25 GB | **restricted**: FLUX.1 [dev] Non-Commercial License | [page](https://huggingface.co/black-forest-labs/FLUX.1-dev) |
| `sam3.1_multiplex_fp16.safetensors` | `models/checkpoints` | 1.75 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/sam3.1) |
| `CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` | `models/clip_vision` | 2.53 GB | not restricted by OpenLayer | [page](https://huggingface.co/h94/IP-Adapter) |
| `control_v11f1p_sd15_depth_fp16.safetensors` | `models/controlnet` | 723 MB | not restricted by OpenLayer | [page](https://huggingface.co/comfyanonymous/ControlNet-v1-1_fp16_safetensors) |
| `control_v11p_sd15_lineart_fp16.safetensors` | `models/controlnet` | 723 MB | not restricted by OpenLayer | [page](https://huggingface.co/comfyanonymous/ControlNet-v1-1_fp16_safetensors) |
| `control_v11p_sd15_scribble_fp16.safetensors` | `models/controlnet` | 723 MB | not restricted by OpenLayer | [page](https://huggingface.co/comfyanonymous/ControlNet-v1-1_fp16_safetensors) |
| `flux-2-klein-4b-fp8.safetensors` | `models/diffusion_models` | 4.07 GB | not restricted by OpenLayer | [page](https://huggingface.co/black-forest-labs/FLUX.2-klein-4b-fp8) |
| `flux1-fill-dev.safetensors` | `models/diffusion_models` | 23.80 GB | **restricted**: FLUX.1 [dev] Non-Commercial License | [page](https://huggingface.co/black-forest-labs/FLUX.1-Fill-dev) |
| `flux2-dev-Q4_K_M.gguf` | `models/diffusion_models` | 20.08 GB | **restricted**: FLUX.2 [dev] Non-Commercial License | [page](https://huggingface.co/city96/FLUX.2-dev-gguf) |
| `krea2_turbo_fp8_scaled.safetensors` | `models/diffusion_models` | 13.14 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/Krea-2) |
| `qwen_image_2.1_int8_convrot.safetensors` | `models/diffusion_models` | 7.26 GB | **restricted**: Qwen Research License Agreement | [page](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) |
| `qwen_image_edit_2511_int8_convrot.safetensors` | `models/diffusion_models` | 20.50 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/Qwen-Image-Edit) |
| `qwen_image_layered_fp8mixed.safetensors` | `models/diffusion_models` | 20.53 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/Qwen-Image-Layered_ComfyUI) |
| `seedvr2_3b_int8_convrot.safetensors` | `models/diffusion_models` | 3.46 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/SeedVR2) |
| `z_image_turbo_bf16.safetensors` | `models/diffusion_models` | 12.31 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/z_image_turbo) |
| `ip-adapter-plus_sd15.safetensors` | `models/ipadapter` | 98 MB | not restricted by OpenLayer | [page](https://huggingface.co/h94/IP-Adapter) |
| `big-lama.pt` | `models/lama` | 206 MB | not restricted by OpenLayer | [page](https://github.com/advimman/lama) |
| `Florence-2-base-PromptGen-v2.0` | `models/LLM` | folder | not restricted by OpenLayer | [page](https://huggingface.co/MiaoshouAI/Florence-2-base-PromptGen-v2.0) |
| `Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors` | `models/loras` | 850 MB | not restricted by OpenLayer | [page](https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning) |
| `qwen-image-edit-2511-multiple-angles-lora.safetensors` | `models/loras` | 295 MB | not restricted by OpenLayer | [page](https://huggingface.co/fal/Qwen-Image-Edit-2511-Multiple-Angles-LoRA) |
| `Z-Image-Turbo-Fun-Controlnet-Union-2.1-lite-2602-8steps.safetensors` | `models/model_patches` | 2.02 GB | not restricted by OpenLayer | [page](https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union-2.1) |
| `Z-Image-Turbo-Fun-Controlnet-Union-2.1.safetensors` | `models/model_patches` | 6.71 GB | not restricted by OpenLayer | [page](https://huggingface.co/alibaba-pai/Z-Image-Turbo-Fun-Controlnet-Union-2.1) |
| `clip_l.safetensors` | `models/text_encoders` | 246 MB | not restricted by OpenLayer | [page](https://huggingface.co/comfyanonymous/flux_text_encoders) |
| `mistral_3_small_flux2_fp8.safetensors` | `models/text_encoders` | 18.03 GB | **restricted**: FLUX.2 [dev] Non-Commercial License | [page](https://huggingface.co/Comfy-Org/flux2-dev) |
| `qwen_2.5_vl_7b_fp8_scaled.safetensors` | `models/text_encoders` | 9.38 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI) |
| `qwen_3_4b.safetensors` | `models/text_encoders` | 8.04 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/z_image_turbo) |
| `qwen3vl_4b_fp8_scaled.safetensors` | `models/text_encoders` | 5.24 GB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/Krea-2) |
| `qwen3vl_8b_w4a8.safetensors` | `models/text_encoders` | 6.31 GB | **restricted**: Qwen Research License Agreement | [page](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) |
| `t5xxl_fp16.safetensors` | `models/text_encoders` | 9.79 GB | not restricted by OpenLayer | [page](https://huggingface.co/comfyanonymous/flux_text_encoders) |
| `4x-UltraSharp.pth` | `models/upscale_models` | 67 MB | not restricted by OpenLayer | [page](https://huggingface.co/Kim2091/UltraSharp) |
| `ae.safetensors` | `models/vae` | 335 MB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/z_image_turbo) |
| `flux2-vae.safetensors` | `models/vae` | 336 MB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/flux2-dev) |
| `full_encoder_small_decoder.safetensors` | `models/vae` | 250 MB | not restricted by OpenLayer | [page](https://huggingface.co/black-forest-labs/FLUX.2-small-decoder) |
| `qwen_image_2.1_vae_bf16.safetensors` | `models/vae` | 676 MB | **restricted**: Qwen Research License Agreement | [page](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) |
| `qwen_image_layered_vae.safetensors` | `models/vae` | 254 MB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/Qwen-Image-Layered_ComfyUI) |
| `qwen_image_vae.safetensors` | `models/vae` | 254 MB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/Krea-2) |
| `seedvr2_ema_vae_fp16.safetensors` | `models/vae` | 501 MB | not restricted by OpenLayer | [page](https://huggingface.co/Comfy-Org/SeedVR2) |

Restricted models are only downloaded with `-IncludeLicenseRestricted -AcceptLicenses`.
