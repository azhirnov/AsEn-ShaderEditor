Size and content of GBuffer in games.


## Assasin's Creed Unity

### GBuffer pass

* RG16_UNorm - UV in virtual texture
* R32U - tangent frame as quaternion
* Depth - TODO ?

**Total:**
* color: 8 bytes
* depth-stencil: 3..5
* sum: 11..13 bytes

Reference:
* [Siggraph2015: GPU-Driven Rendering Pipelines](https://advances.realtimerendering.com/s2015/aaltonenhaar_siggraph2015_combined_final_footer_220dpi.pdf)


## Fallout 4

### GBuffer pass

* Color0 - sRGB8_A8 - diffuse from texture
* Color1 - RG16_UNorm - normals
* Color2 - RGBA8_UNorm - ?
* Color3 - RGBA8_UNorm - ?
* Color4 - sRGB8_A8 - unused?
* Color5 - RG16F - unused?
* Depth - D24
* Stencil - S8 - mask for dynamic objects?

**Total:**
* color: 32+(16) bytes
* depth-stencil: 4 bytes packed
* sum: 34+(16) bytes


## Horizon Zero Dawn (PC)

### GBuffer pass

* Color0 - sRGB8_A8 - diffuse from texture
* Color1 - RGBA16F - unused?
* Color2 - RG16_UNorm - normals
* Color3 - RGBA16F - material params ?
* Color4 - RGBA8_UNorm - material params ?
* Depth - D32F
* Stencil - S8 - [0..7] checkerboard, other - dynamic objects?

**Total:**
* color: 28+(8) bytes
* depth-stencil: 5 bytes packed
* sum: 33+(8) bytes


## Horizon Forbidden West (PC)

### GBuffer pass

* Color0 - sRGB8_A8 - diffuse from texture
* Color1 - R11G11B10F - unused?
* Color2 - RG16_UNorm - normals
* Color3 - RG16F - material params ?
* Color4 - RGBA8_UNorm - material params ?
* Color5 - RG16F - unused ?
* Color6 - R16F - unused ?
* Depth - D32F - reverseZ
* Stencil - S8 - unused ?

**Total:**
* color: 16+(10) bytes
* depth-stencil: 4 bytes packed
* sum: 20+(10) bytes


## Ghost Recon Wildlands

### GBuffer pass

* Color0 - sRGB8_A8 - diffuse from texture
* Color1 - RGBA8_UNorm - normals
* Color2 - sRGB8_A8 - PBR params from texture
* Color3 - RGBA8_UNorm - thermal?
* Color4 - R11G11B10F - light buffer?
* Color5 - RG16F - ?
* Depth - D32F - reverseZ
* Stencil - I8 - material ID ?

**Total:**
* color: 24 bytes
* depth-stencil: 5 bytes packed
* sum: 29 bytes

### After GBuffer pass

HDR color target: RGBA16F - after GBuffer pass


## Cyberpunk 2077

### GBuffer pass

* Color0 - RGB10A2_UNorm - diffuse
* Color1 - RGB10A2_UNorm - normals
* Color2 - RGBA8_UNorm - material params ?
* Depth - D32F - reverseZ
* Stencil - I8 - ?

**Total:**
* color: 12 bytes
* depth-stencil: 5 bytes packed
* sum: 17 bytes

### After GBuffer pass

Velocity: RGBA16F - separate GBuffer pass (4RT + DS)

HDR color target: RGBA16F - after GBuffer pass
