
# Descriptor Pool

[Исходник теста](https://github.com/azhirnov/as-en/blob/dev/AE/engine/performance/graphics/Vulkan/VkTest_DescriptorPool.cpp).

### ARM Mali

**Valhall gen1** & **Valhall gen3** выделяют память строго по типу дескриптора.

### Adreno

Adreno использует общую память и создает столько дескрипторов, сколько возможно уместить.
Размер дескриптора в сравнении с StorageBuffer дескриптором.

|                      | 500 | 600 | 700 | 800 |
|----------------------|-----|-----|-----|-----|
| StorageBuffer        |     |  1  |     |  1  |
| UniformBuffer        |     |  1  |     |  1  |
| StorageImage         |     |  1  |     |  2  |
| SampledImage         |     |  1  |     |  2  |
| CombinedImage        |     | 1/3 |     | 2/3 |
| DynamicUniformBuffer |     |  1  |     |  2  |
| DynamicStorageBuffer |     |  1  |     |  2  |

Судя по результатам SampledImage хранит не сам дескриптор, а ссылки на 2 дескриптора, поэтому занимает меньше всего места.


### AMD

RDNA3 на Windows -

RDNA3 RADV -


### Intel

UHD 620 на Windows - Buffer и DynamicBuffer занимают общую память, все 4 дескриптора одинакового размера.
Нельзя создать текстуры в пуле для буферов, но наоборот можно.

UHD Graphics 730 (gen12?) -

Arc140T (Xe+LP) на Windows - использует общую память, но все дескрипторы одинакового размера.


### NVIDIA

На NV память никак не ограничена, можно создать пул под один дескриптор, а создать 10К.
Ограничено только количество наборов дескрипторов.


### PowerVR

BXM - для 8 запрошеных дескрипторов резервирует место под 12800 любого типа.


# Mutable Descriptor Type

[Исходник теста](https://github.com/azhirnov/as-en/blob/dev/AE/engine/performance/graphics/Vulkan/VkTest_MutableDescriptorType.cpp)

NVIDIA - поддерживает все типы дескрипторов.

Intel Xe+LP - не поддерживает только CombinedImage.


**Не поддерживается**

* Mali G57
* Mali G610
* PowerVR BXM
