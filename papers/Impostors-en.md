Drawing highly detailed geometry at a distance is very expensive:

* Small triangles cause significant quad overdraw.
* A large number of vertices strain the vertex shader (VS).
* Overlapping triangles add to pixel overdraw.
* Diverse textures burden the texture cache.
* On older hardware, without bindless textures, it's even more resource-intensive due to frequent bindings of new textures.

Moreover, distant geometry is only visible from one angle, and camera movement doesn't reveal noticeable changes. Therefore, for optimization, the model is baked into a 2D imposter. Typically, this imposter contains the same information as the GBuffer: color, normals, and PBR parameters.


### GR: Wildlands

![](img/grw/screenshot1.jpg)

In the screenshot, only two types of trees are drawn, represented by simple 2D textures with normal maps.
Randomization is achieved through the rotation of the normal map.
Atmospheric haze, blur, and cloud shadows further obscure the repeating imposters.

Such tree imposters effectively mask the low texture detail on distant mountains.
On modern hardware, there's no point in reducing detail this way, especially in 4K where it becomes too noticeable.
This optimization is only necessary for built-in devices and mobiles with slow DDR/LPDDR memory.

![](img/grw/TreeImpostors.jpg)

Buildings use a 2Kx2K texture atlas and are modeled as 3D objects, which are slightly more complex than cubes.
This isn't a true imposter but rather the lowest level of detail (LOD).

![](img/grw/BuildingImpostors.jpg)
