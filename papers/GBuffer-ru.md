

# Horizon Forbidden West (PC)



# Ghost Recon Wildlands

* Color0 - sRGB8_A8 - diffuse from texture
* Color1 - RGBA8_UNorm - normals
* Color2 - sRGB8_A8 - PBR params from texture
* Color3 - RGBA8_UNorm - thermal?
* Color4 - R11G11B10F - light buffer?
* Color5 - RG16F - ?
* Depth - D32F - reverseZ
* Stencil - I8 - material ID ?

Total:
* color: 24 bytes
* depth-stencil: 4 bytes + 1 byte
* sum: 29 bytes

HDR color target: RGBA16F - after GBuffer pass


# Cyberpunk 2077

* Color0 - RGB10A2_UNorm - diffure
* Color1 - RGBA10A2_UNorm - normals
* Color2 - RGBA8_UNorm - material params ?
* Depth - D32F - reverseZ
* Stencil - I8 - ?

Total:
* color: 12 bytes
* depth-stencil: 4 bytes + 1 byte
* sum: 17 bytes

Velocity: RGBA16F - separate GBuffer pass (4RT + DS)

HDR color target: RGBA16F - after GBuffer pass
