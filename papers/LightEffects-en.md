## Glow

In Doom 2016, the effect consists of two parts:
* A standard bloom with downscaling
* A separate RT where flares are drawn using several sprites.

Then, the two parts are combined, with bloom additionally combined with lensDirt.

![](img/doom/Bloom_LensFlares.jpg)

In Horizon Zero Dawn, the light from robots is similarly implemented. The lens flares are drawn using geometry.

This separation is necessary because bloom produces a uniform, blurry image, while pre-drawn sharp sprites add a more visually appealing look and mimic the scattering of light on the lens.

What happens when only bloom is used can be seen in Unreal Tournament 3 and other games of that time, where the image became too blurry.


Another version of the effect is analyzed in [Doom 3 – Volumetric Glow](https://simonschreibt.de/gat/doom-3-volumetric-glow/).
A cheaper effect is built using geometry and a gradient texture is applied, or the falloff is calculated in FS. However, it's important to note that interpolation can produce artifacts at the edges of the geometry, so the distance should be calculated after interpolation.

If the geometry construction is refined, it can also mimic volumetric light.
However, this approach requires OIT, unlike Bloom.

![](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/docs/img/FakeGlow.jpg)

[Example](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/vfx/FakeGlow.as)


## Light Volume

In Doom 2016, as in Doom 3, volumetric light is drawn using geometry.

![](img/doom/VolumeLight.jpg)

Additionally, in Doom 2016, there's an attempt to mimic the lighting of smoke. It's also done using geometry, which looks good from the side, but when looking directly at the light source, the geometry unrealistically shifts to the side.

![](img/doom/VolumetricLight2.jpg)


![](img/doom/VolumetricLight3.jpg)

The effect is analyzed in the video [A Game Engine Built For Optimisation](https://www.youtube.com/watch?v=i6VVegoRuy0).<br/>
Here, the sun rays breaking through the tree canopy are defined as stretched sprites.
For the forest, the sprites are randomly scattered, with density depending on the transparency of the tree canopy.

![](img/other/LightShaftSprite.jpg)


In Cyberpunk 2077, the effect was implemented using volume marching and added temporal techniques and DLSS for optimization.
As a result, on the first appearance of the effect on the screen, only one pixel from a 2x2 or 4x4 square is drawn, and only after 8/16 frames is the effect fully rendered, but by that time the camera has moved and reprojection errors appear.

![](img/cp/VolumeLightDLSS.jpg)

A detailed breakdown of how to create the effect using sprites is provided in [Light beam shader in godot](https://passivestar.xyz/posts/light-beam-shader-in-godot/)
![](https://passivestar.xyz/posts/light-beam-shader-in-godot/cover_hu_a49b8b2f6c12256e.jpg)


## Light Bulbs

![](img/grw/LightBulbs.jpg)

In GTA V and Ghost Recon Wildlands, sprites are used to draw distant light sources.
The effect serves as an addition to Bloom, as when light sources are too far away, their geometry may not even be drawn, causing them to not appear in Bloom.

It's analyzed in [GTA V - Graphics Study - Part 2](https://www.adriancourreges.com/blog/2015/11/02/gta-v-graphics-study-part-2/).

Visibility is checked using a per-pixel depth test, which creates artifacts when the light source (Light bulb) is partially occluded by geometry.
This behavior is physically incorrect - a large bright spot appears due to the scattering of light on the lens, which is always round.
Therefore, partial occlusion by geometry during a per-pixel depth test results in an incorrect image.

A more correct approach is to perform the depth test only for a single pixel or a square, and based on the test result, decide whether to draw the light bulb or not.

Objects in front of the light source can partially obscure it, so less light reaches the lens.


## Screenspace Light Shafts

A quick version of the effect looks like this:
* Create a mask using the depth buffer, the sky is considered as 1, everything else as 0. For optimization, it's done at 1/4 of the screen resolution.
* Multiply the mask by the color of the sun/moon.
* Apply a radial blur centered at the position of the sun.
  For optimization, the radial blur is done in two passes with different steps. The first pass produces a step-like image, while the second smooths it out. However, the two-pass version gives a different shape to the rays, which looks even nicer.
* The blurred image is added to the color.

Details:
* Since the effect works in 2D, it can create artifacts when a light ray is drawn over an object, whereas in 3D it should be behind it.
* After blurring, the color near the sun remains very bright, and when combined with the sun's brightness, it doubles and the nearby sky becomes overexposed, which looks bad.
  When applying the effect, the brightness should be adjusted, taking into account that it's an approximation of light scattering by dust and mist/fog particles, and the emitted light comes from the angle between the light and the camera, based on the density of the mist.

The effect is relatively cheap and can be applied multiple times, for example, separately to clouds for the effect of crepuscular rays (scattering of light in atmospheric haze) and separately to scene objects to mimic scattering in fog or dust.
Additionally, the effect can be applied separately to all bright light sources on the scene, creating a cheap approximation of volumetric light (volumetric light).

![](img/hzd/LightShafts.jpg)

[Example](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/vfx/LightShafts.as)


[GDC2014: Adding High-End Graphical Effects to GT Racing 2 on Android x86 (slides 15-21)](https://gdcvault.com/play/1020220/Adding-High-End-Graphical-Effects) - another version of the effect.
Here, only the sun's point is blurred, resulting in the same rays but without shadows. Therefore, for a more attractive effect, it's important to draw an area much larger than the sun.

![](img/gdc/IntelLightShafts.png)


A more expensive, but physically correct version is implemented in Fallout 4 using NVIDIA Volumetric Lighting ([pdf](https://d29g4g2dyqv443.cloudfront.net/sites/default/files/akamai/gameworks/downloads/papers/NVVL/Fast_Flexible_Physically-Based_Volumetric_Light_Scattering.pdf), [video](https://gdcvault.com/play/1023519/Fast-Flexible-Physically-Based-Volumetric)).

* A shadow map is rendered for the light source (sun).
* Geometry is constructed from the shadow map and stretched.
* The geometry is drawn with a depth test, where visible geometry starts the marching to physically correctly calculate light scattering.

![](img/gdc/NVLightShafts.jpg)



## Bloom

Scattering of light on the lens. The brighter the light, the larger the area/blur radius.

The effect consists of several parts:
* The brightest pixels from the HDR color are extracted.
	- In Doom 2016, the maximum brightness is taken component-wise, resulting in a slightly distorted color.
* Generation of mips with blur.
* Upscaling, lower mips are added to the higher ones.
* Before tonemapping, the top blurred mip is added to the scene color.

Examples:
* [Gaussian blur, without optimizations](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/perf/Blur-1.as)
* [Gaussian blur in two passes](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/perf/Blur-2.as)
* [Dual filter blur, faster on mobile](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/perf/Blur-3.as)
* [Kawase blur, similar to Dual filter](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/perf/Blur-4.as)
* [Bloom](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/samples-2d/Bloom.as)

