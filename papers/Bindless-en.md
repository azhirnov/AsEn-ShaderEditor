Table of Contents:
* [Advantages](#Advantages)
* [Bindless](#Bindless)
  - [Bindless in Vulkan](#Bindless-in-Vulkan)
  - [Bindless in Metal](#Bindless-in-Metal)
* [GPU-Driven Rendering](#GPU-Driven-Rendering)
* [Performance Tests](#Performance-Tests)
* [Conclusion](#Conclusion)

# Advantages

First, it's important to understand how rendering works.

In TBR and TBDR architectures, a single warp can fill multiple triangles, reducing the number of waiting threads.
However, a warp can only execute one shader and one set of states at a time.
Therefore, two draw calls with the same Pipeline and DescriptorSet may end up in the same fragment shader warp, but if a different DescriptorSet is bound, this won't happen, potentially doubling the number of warps needed in some cases.
The denser the geometry, the more critical it is for fragment shaders to fully utilize warps.
The bindless approach helps by binding a single DescriptorSet and selecting the required resource by ID in the shader.

In a tile-based architecture, there are other considerations. AMD discusses some aspects in their article [Understanding GPU Context Switching](https://gpuopen.com/learn/understanding-gpu-context-rolls/). The hardware supports 7 contexts that execute draw commands in parallel, but each state change consumes one context. Thus, a bindless approach sets the state once and runs parallel rendering in 6 contexts, whereas setting states for each draw call results in 3 states and 3 parallel renders, effectively halving the workload.


# Bindless

The idea is to bind all resources once and select the needed buffers and textures in the shader by ID.

There's an older bindless model where each draw call specifies an index into resources, and a newer model where the resource index can change within a single draw call.

The newer bindless approach allows GPU-Driven Rendering with culling and visibility checks on the GPU side.
It also enables techniques like Deferred Texturing and Visibility Buffer, where texture reads happen in post-processing.


## Performance

Even older mobile devices supporting Vulkan can handle bindless well, but there are nuances.

For Adreno, it's recommended to use `VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER` because of how Adreno GPUs handle Bindless mode.
Using a combined image sampler allows the GPU to use Bindless mode, which is more performant. Separate samplers fall back to a slower mode, with performance tests showing a 2-5% decrease in fill rate.

For Mali, bindless descriptor sets work well with combined resources, allowing indexing into texture and buffer arrays.
However, you cannot use constructions like `sampler2D(un_Textures[tex_id], un_Samplers[samp_id])`.


## Bindless in Vulkan

`shaderStorageBufferArrayDynamicIndexing` and other features are supported in Vulkan 1.0 and determine if dynamic indexing of resource arrays is allowed.
All indices within a warp must be uniform; otherwise, it's undefined behavior. If unsupported, array access is only allowed via constant indices.

Additionally, you can select a layer from a texture array (sampler2DArray) where the layer may be non-uniform.

<details><summary>Support for shaderSampledImageArrayDynamicIndexing and shaderStorageBufferArrayDynamicIndexing starts with:</summary>

* Adreno 500
* AMD GCN1?
* Apple A9
* Intel gen9
* Mali Midgard Gen3
* NVidia Kepler/GTX600?
* PowerVR Series 8

</details>

### Descriptor Indexing

The extension `VK_EXT_descriptor_indexing` (added in 1.x.72) enables bindless techniques. However, beyond supporting the extension, there are various options that may not be universally supported.

`shaderSampledImageArrayNonUniformIndexing` and others determine if dynamic indexing of resource arrays is allowed when the index varies within a warp (non-uniform).
In shaders, the index must be explicitly marked as [nonuniformEXT](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GL_EXT_nonuniform_qualifier.txt): `resource[nonuniformEXT(index)]`.
The minimal set of options widely supported across most GPUs can be viewed in [min_nonuniform_desc_idx](https://github.com/azhirnov/as-en/blob/dev/AE/engine/shared_data/feature_set/parts/min_nonuniform_desc_idx.as).
Older GPUs only support `shaderSampledImageArrayNonUniformIndexing`, so buffers must be stored in RGBA32F textures, a format widely supported but without linear filtering.

In Vulkan 1.4, the `VK_EXT_descriptor_indexing` extension became part of the core, while it was optional in 1.2. At minimum, `shaderUniformTexelBufferArrayDynamicIndexing` and `shaderStorageTexelBufferArrayDynamicIndexing` must be supported.

`shaderSampledImageArrayNonUniformIndexingNative` and others determine how access to resources is implemented when the index varies within a warp. If hardware support is lacking, the code compiles into a waterfall loop - iterating over all unique index values within the warp.

Ray tracing acceleration structures always allow non-uniform access.

<details><summary>*NonUniformIndexing support starts with:</summary>

* Adreno 600 *(all options, including Native)*
* AMD GCN1 *(all options except InputAttachment)*
* Apple A9 *(all options and shaderSampledImageArrayNonUniformIndexingNative)*
* Intel gen9? *(all options)*
* Mali Valhall gen1 *(all options and shaderStorageBufferArrayNonUniformIndexingNative)*
* Maleoon 9xx *(all options except InputAttachment)*
* NVidia Kepler/GTX600? *(all options, including Native)*
* PowerVR B-Series *(all options, including Native)*

</details>

The extension `VK_EXT_descriptor_indexing` also adds useful flags `VkDescriptorBindingFlags`:
* `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT` - requires the `descriptorBindingPartiallyBound` feature. Marks descriptors that __will not be dynamically indexed__.
	- Allows storing invalid descriptors if they're not statically accessed from the shader.
	- Without this flag, the driver assumes all descriptors are valid.
	- If dynamic indexing is present, all array elements must be valid. *(In older examples, the flag was misused, now validation layers issue errors.)*
* `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` - requires the `descriptorBindingVariableDescriptorCount` feature. Allows the last descriptor to be of variable size. The size is set when creating the descriptor set.
* `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` - requires options like `descriptorBindingSampledImageUpdateAfterBind` for each resource type. Allows updating descriptors after `vkBindDescriptorSet`.
	- Updates must happen before submitting the command buffer to the GPU.
	- The last set descriptor is used.
	- Descriptors can be updated from multiple threads, requiring synchronization only when updating the same descriptor simultaneously.
* `VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT` - requires the `descriptorBindingUpdateUnusedWhilePending` feature. Allows updating unused descriptors while the GPU is executing commands using this descriptor set.
	- Descriptors can be updated from multiple threads, requiring synchronization only when updating the same descriptor.
	- TODO VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT


### Nonuniform

Uniform data does not change within a draw call `vkCmdDraw***`.

Data considered uniform:
* Data from uniform buffers and push constants.
* `gl_DrawID`.
* For compute shaders: Same values within a workgroup, e.g., `gl_WorkGroupID`.

Non-uniform data includes:
* `gl_VertexIndex`, `gl_PrimitiveID`, vertex attributes, etc.
* `gl_LocalInvocationID` and `gl_GlobalInvocationID`.
* `gl_InstanceIndex` on TBDR architectures, as fragment shaders for primitives from different instances may end up in the same warp.
* `gl_BaseInstance`, `gl_BaseVertex`, `gl_ViewIndex` ???

When using `nonuniform()`, the compiler may add extra instructions. If the compiler knows the variable is only `uniform`, it ignores `nonuniform()`, avoiding unnecessary instructions.
The example [UniqueIDs](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/compute/UniqueIDs-1.as) shows how the compiler converts non-uniform resource access into uniform.

The example [BrokenNonuniform](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/nonuniform/BrokenNonuniform.as) demonstrates what happens if `nonuniform()` isn't used.
On most tested GPUs, the driver detects non-uniformity, and `nonuniform()` has no effect, making such errors hard to catch. Only on AMD GCN does using `nonuniform()` immediately reveal issues.

For more details, refer to [Vulkan Samples: descriptor indexing](https://github.com/KhronosGroup/Vulkan-Samples/tree/main/samples/extensions/descriptor_indexing#non-uniform-indexing-enabling-advanced-algorithms).

There's also the parameter `quadDivergentImplicitLod`, which determines if the driver can compute LOD for textures when the index varies across a quad.

> If the image or sampler object used by an implicit derivative image instruction is not uniform across the quad and `quadDivergentImplicitLod` is not supported, then the derivative and LOD values are undefined.

No issues arise when the same index is used for triangles, as even on mobile devices, when multiple triangles are merged into a single warp, they're always rasterized as quads. For visibility buffers, derivatives are already computed per-pixel. However, there's still an issue with relief mapping and post-processing with tracing, where per-pixel divergent behavior is possible.

If per-pixel index changes are necessary, manual derivative calculation is required:
```
float2 dx = dFdx(uv) * Exp2(bias);
float2 dy = dFdy(uv) * Exp2(bias);
textureGrad(un_Textures[nonuniform(tex_id)], dx, dy);
```

Support for `quadDivergentImplicitLod` depends on the GPU vendor, not the architecture version.
It's supported by Adreno, Intel, NVidia, PowerVR, but not by AMD, Apple, Mali, VideoCore, or Maleoon.

The example [QuadDivergentImplicitLod](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/nonuniform/QuadDivergentImplicitLod.as) demonstrates whether an error occurs if `textureGrad()` isn't used.
On AMD RX570, the difference is only in `textureQueryLod().x`.
NVidia, Intel, and PowerVR show minimal differences between `texture()` and `textureGrad()`, possibly due to lower precision when derivatives are computed implicitly.

With Mali, it's more complex - `textureQueryLod(nonuniform(...))` doesn't work at all, while `textureGrad(nonuniform(...), dFdx(), dFdy())` shows worse filtering at a distance. Mali's optimization recommendations even advise against using `textureGrad` if possible.

Older Mali Midgard GPUs don't support `nonuniform()`, but behave similarly to newer Mali Valhall GPUs.
On Adreno 500, non-uniform texture access doesn't work at all - texture reads return black.

### Device Address

The extension `VK_KHR_buffer_device_address` allows using pointers to buffer memory. The address is obtained from `ulong` or `uint2` types.
[Example](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/compute/BufferReference.as) with a binary tree.

<details><summary>Support starts with:</summary>

* Adreno 600
* AMD GCN1
* Intel gen9?
* Mali Bifrost gen1
* Maleoon 9xx
* NVidia Kepler/GTX600?
* PowerVR Series 8

</details>

### Descriptor Buffer

The extension `VK_EXT_descriptor_buffer` simplifies descriptor management by using a buffer that stores descriptors instead of abstract descriptor sets and pools.
For more details, see [proposal](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_descriptor_buffer.adoc) and [blog](https://www.khronos.org/blog/vk-ext-descriptor-buffer).

Updating descriptor data is similar to updating a buffer. Descriptor reads in shaders require synchronization, e.g.:
```
dstStage = VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT
dstAccess = VK_ACCESS_2_DESCRIPTOR_BUFFER_READ_BIT_EXT
```
Like with descriptor sets, all descriptors dynamically accessed must be valid.

The extension `VK_EXT_robustness2` introduces support for null descriptors with the `nullDescriptor` feature. It's noted that `nullDescriptor` doesn't impact performance [here](https://github.com/KhronosGroup/Vulkan-Docs/issues/1971#issuecomment-1308974805). Other robustness extensions can significantly impact performance.

<details><summary>Support starts with:</summary>

* Adreno 800/X1 (starting with driver 512.800.0)
* Adreno Turnip 600 (open-source driver)
* AMD GCN4
* Intel Xe-HP
* Intel Xe+LP (Arc 140T)
* Mali Valhall gen3 (starting with driver 53.0.0)
* NVidia Kepler/GTX7xx

</details>

### Limits

Newer GPUs support hundreds of textures per shader and are generally well-suited for bindless approaches. However, older models may still have limits, such as 16-32 textures.

<details><summary>Hundreds of textures supported:</summary>

* Adreno 500 (128 textures, 158 resources total)
* Adreno 600 (up to 524,288 of each resource type, 1,572,864 total)
* AMD GCN1 (up to 4,294,967,295 of each resource type)
* Apple M1 (128 textures, 159 resources total) ???
* Intel gen9 (200 textures, 200 resources total)
* Intel Xe-HP, Xe+LP (up to 33,554,432 of each resource type)
* Mali Bifrost gen1 (256 textures, 361 resources total)
* Mali Valhall gen1 (up to 500,000 of each resource type, 500,000 total)
* Maleoon 9xx (up to 500,000 of each resource type, 2,000,016 total)
* NVidia Kepler/GTX600 (up to 1,048,576 of each resource type)
* PowerVR Series 9 (48 textures, 224 resources total)
* PowerVR B Series (up to 4,294,967,295 of each resource type)

</details>

## Bindless in Metal

TODO

# GPU-Driven Rendering

Bindless techniques enable moving more logic to the GPU.

The main downside is difficulty in debugging. Out-of-bounds array accesses don't always cause crashes; crashes only occur when accessing beyond memory page boundaries, introducing randomness.

## Prefix Scan

One stage of GPU-Driven rendering involves checking object visibility and removing invisible objects from the rendering queue. Visibility checks are performed using frustum culling, [HiZ](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/papers/GeometryCulling-ru.md#hierarchy-z-buffer-hzb-hiz), [Raster occlusion](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/papers/GeometryCulling-ru.md#raster-occlusion), and others. After visibility checks, we get an array of object IDs and empty elements. To group IDs, a prefix scan/prefix sum algorithm is used. Examples: [PrefixScan-1](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/compute/PrefixScan-1.as), [PrefixScan-2](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/compute/PrefixScan-2.as).

If the order of IDs doesn't matter, a simpler algorithm with atomics can be used. Example: [PrefixScan-3](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/compute/PrefixScan-3.as), with flickering due to atomic operations.

## Radix Sort

One important optimization in rendering is sorting objects by distance from the camera, allowing early Z-culling of invisible pixels. Sorting is most efficient after visibility checks, as fewer objects remain and sorting requires fewer iterations.

Conversely, when submitting a scene for rendering, objects are already partially sorted, such as through a quad-tree or octree, where each node contains a set of geometry, potentially thousands of triangles. When traversing the tree from the camera, nodes are added in the correct order, leaving only sorting within the node and at the boundaries.

For sorting, it's effective to split the screen into tiles and perform sorting within each tile.

Examples: TODO

## Multi Draw Indirect

The extension `VK_KHR_draw_indirect_count` (added to the core in 1.2) isn't widely adopted, making the code non-universal, so it's better to avoid using it.

<details><summary>Supported starting with:</summary>

* AMD GCN1
* Adreno 600
* Samsung Xclipse 530
* PowerVR Series 8
* NVidia Kepler/GTX600?
* Intel gen9?
* Mali Valhall gen3

Unsupported on Apple, as Metal has its own mechanism.

</details>

The core Vulkan 1.0 option `drawIndirectFirstInstance` allows using the `firstInstance` field in `VkDrawIndexedIndirectCommand`. <details><summary>Unsupported on a small number of devices:</summary>

* Adreno 500
* PowerVR Series 6

</details>

There's also the option `multiDrawIndirect` and the limit `maxDrawIndirectCount`, affecting the `drawCount` parameter in `vkCmdDrawIndexedIndirect()`. Often supported, but `maxDrawIndirectCount=1` is equivalent to no support. <details><summary>Unsupported:</summary>

* Mali up to Valhall gen2 (T880, G71, G72, G76, G77, G78)
* Mali Panfrost driver on Linux
* Adreno 500

</details>

When `maxDrawIndirectCount=1`, the fallback is to use instancing with a fixed number of indices. Geometry is split into uniform-sized meshes; if fewer vertices are needed, extra vertices write NaN to the position.

## Per Instance Vertex Rate

Also known as Vertex Attribute Divisor. Allows instance data to be passed through the vertex buffer, which can be faster on older hardware where storage buffers are slow.

This approach is described in [Optimizing the Graphics Pipeline with Compute](https://gdcvault.com/play/1023109/Optimizing-the-Graphics-Pipeline-With) (slide 23).

# Performance Tests

[In a separate document](tests/BindlessTests3-ru.md)

# Conclusion

Unexpectedly, Adreno 660 performed poorly with bindless. Intel gen9.5 had issues with bindless textures and immutable samplers, but this was fixed on a similar-performance N150 (gen12?).

Three groups were identified:
1. When bindless textures + immutable samplers are faster. Example: AMD 780M RADV.
2. When bindless textures + bindless samplers are faster. Example: Intel UHD620, PowerVR BXM, Adreno 660, Mali G57.
3. No difference in performance with bindless. Example: Intel N150, Mali G610, AMD 780M PRO and VLK, AMD RX570, NV RTX 2080.

The tests showed that `*NonUniformIndexingNative` parameters have no impact: performance always decreases, and `nonuniform()` is only needed for AMD GCN.

On older devices like Mali T830 and Adreno 505, `nonuniform()` isn't supported, allowing only 16 textures to be bound. However, even older Mali T830 supports non-uniform texture access.
