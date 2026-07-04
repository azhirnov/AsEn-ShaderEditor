Оглавление:
* [В чем преимущество](#В-чем-преимущество)
* [Bindless](#Bindless)
	- [Bindless в Vulkan](#Bindless-в-Vulkan)
	- [Bindless в Metal](#Bindless-в-Metal)
	- [Что лучше](#Что-лучше)
* [Тесты производительности](#Тесты-производительности)
* [Итоги](#итоги)


# В чем преимущество

Для начала нужно понять как работает рисование.

В TBR и TBDR архитектурах один варп может закрашивать несколько треугольников, это позволяет уменьшить количество простаивающих потоков.
Но варп может выполнять только один шейдер и один набор состояний.
Так два вызова рисования с одинаковым Pipeline и DescriptorSet могут попасть в один варп в фрагментном шейдере, но если забиндить другой DescriptorSet, то уже нет, а значит в некоторых случаях потребуется в 2 раза больше варпов.
Чем больше плотность геометрии, тем важнее чтобы фрагментные шейдеры полностью заполняли варп.
В этом помогает bindless подход, когда биндится один DescriptorSet, а нужный ресурс выбирается в шейдере по ID.

В дотайловой архитектуре другие особенности.
Часть деталей работы графического пайплайна есть у AMD в статье [Understanding GPU context rolls](https://gpuopen.com/learn/understanding-gpu-context-rolls/).
В железе поддерживается 7 контекстов, которые выполняют команды рисования параллельно, но каждая смена состояний занимает один контекст.
Так bindless вариант выставит состояние один раз и в 6 контекстов запустит параллельное рисование, а выставляя состояния для каждого рисования мы получим 3 состояния и 3 параллельных рисования, то есть в 2 раза меньше работы.

До bindless для аналогичной оптимизации использовали [виртуальные текстуры](VirtualTexturing-ru.md) или атласы и текстурные массивы.

Bindless техники позволяют перенести больше логики на [сторону ГП](#GPUDriven-ru.md).


# Bindless

Идея в том, чтобы забиндить все ресурсы один раз, а в шейдере выбирать нужный буфер и текстуры.

Есть старая модель bindless, когда для каждого рисования задается индекс ресурсов, и более новая, когда индекс ресурса меняется в пределах вызова рисования.

Новая модель bindless позволяет использовать GPU Driven Rendering с сортировкой и отсечением невидимой геометрии на стороне ГП.
Также это позволяет использовать техники типа Deferred Texturing и Visibility Buffer, где чтение текстур идет пост-процессом.


## Производительность

Даже старые мобилки, которые поддерживают Vulkan, хорошо справляются с bindless, но есть нюансы.

Так для Adreno пишут:
> It is recommended to use VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER because of how the Adreno GPU works with Bindless mode. When using a combined image sampler, the GPU can use Bindless mode which is more performant. When using separate samplers, it will fall back to a slower mode. Performance deltas have shown a decrease by 2-5% in the fill rate for separate samplers.

И для Mali:
> A bindless descriptor set will work well with combining resources, allowing indexing into texture and buffer arrays.

То есть сэмплеры надо выставить заранее, нельзя использовать конструкции вида `sampler2D( un_Textures[tex_id], un_Samplers[samp_id] )`.

Учитывая архитектуру ГП проблемы с производительностью могут возникнуть при неоднородности внутри варпа, о чем подробнее написано в [Nonuniform главе](#Nonuniform).

Подробнее о замерах производительности написано в [итогах](#Итоги).


## Bindless в Vulkan

`shaderStorageBufferArrayDynamicIndexing` и другие доступны в ядре Vulkan 1.0, определяет разрешена ли динамическая индексация массива ресурсов.
Но все индексы в пределах варпа должны совпадать (uniform), иначе это неопределенное поведение. Если не поддерживается, то доступ к массиву разрешен только по константным значениям.<br/>
Кроме этого можно по-старинке выбирать слой из текстурного массива (sampler2DArray) и слой может быть неоднородным.

<details><summary>Опции shaderSampledImageArrayDynamicIndexing и shaderStorageBufferArrayDynamicIndexing поддерживаются начиная с:</summary>

* Adreno 500
* AMD GCN1 ?
* Apple A9
* Intel gen9
* Mali Midgard Gen3
* NVidia Kepler/GTX600 ?
* PowerVR Series 8

</details>

### Descriptor Indexing

Расширение `VK_EXT_descriptor_indexing` (добавлено в 1.x.72) позволяет использовать bindless-техники. Но кроме поддержки расширения есть различные опции, которые могут не поддерживаться.

`shaderSampledImageArrayNonUniformIndexing` и другие определяет разрешена ли динамическая индексация массива ресурсов, когда индекс в вределах варпа не совпадает (non-uniform).
В шейдере обязательно помечать индекс как [nonuniformEXT](https://github.com/KhronosGroup/GLSL/blob/master/extensions/ext/GL_EXT_nonuniform_qualifier.txt): `resource[ nonuniformEXT(index) ]`.
Минимальный набор опций, который доступен на большинстве ГП можно посмотреть в [min_nonuniform_desc_idx](https://github.com/azhirnov/as-en/blob/dev/AE/engine/shared_data/feature_set/parts/min_nonuniform_desc_idx.as).
Старые ГП поддерживают только `shaderSampledImageArrayNonUniformIndexing`, поэтому для буферов придется использовать RGBA32F текстуры, этот формат поддерживается у большинства ГП, хоть и без линейной фильтрации.

В Vulkan 1.4 расширение `VK_EXT_descriptor_indexing` сделали обязательным в ядре, до этого с 1.2 оно было опционально. Минимально должны поддерживаться `shaderUniformTexelBufferArrayDynamicIndexing` и `shaderStorageTexelBufferArrayDynamicIndexing`.

`shaderSampledImageArrayNonUniformIndexingNative` и другие `*Native` определяет как будет реализован доступ к ресурсам в случае, когда индекс внутри варпа не совпадает. Если нет поддержки в железе, то код компилируется в waterfall loop - цикл по всем уникальным значениям индекса в пределах варпа.

Для ускоряющих структур (ray tracing acceleration structure) всегда разрешен неоднородный доступ.

<details><summary>Опции *NonUniformIndexing поддерживается начиная с:</summary>

* Adreno 600 *(все опции, включая Native)*
* AMD GCN1 *(все опции, кроме InputAttachment)*
* Apple A9 *(все опции и shaderSampledImageArrayNonUniformIndexingNative)*
* Intel gen9 ? *(все опции)*
* Mali Valhall gen1 *(все опции и shaderStorageBufferArrayNonUniformIndexingNative)*
* Maleoon 9xx *(все опции, кроме InputAttachment)*
* NVidia Kepler/GTX600 ? *(все опции, включая Native)*
* PowerVR B-Series *(все опции, включая Native)*

</details>

Расширение `VK_EXT_descriptor_indexing` также добавляет полезные флаги `VkDescriptorBindingFlags` :
* `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT` - требует опцию `descriptorBindingPartiallyBound`, помечает дескрипторы, которые __не будут динамически индексироваться__.
	- Позволяет хранить невалидные дескрипторы, если к ним нет __статичных обращений__ из шейдера.
	- Без этого флага драйвер считает, что все дескрипторы валидны.
	- Если есть динамическая индексация, то все элементы массива должны быть валидны. *(В старых примерах флаг используется неправильно, сейчас слои валидации выдают ошибку)*.
* `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` - требует опцию `descriptorBindingVariableDescriptorCount`, позволяет сделать последний дескриптор переменного размера. Размер устанавливается при создании дескриптор сета через структуру `VkDescriptorSetVariableDescriptorCountAllocateInfo`.
* `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` - требует опции `descriptorBindingSampledImageUpdateAfterBind` и другие для каждого типа ресурсов. Позволяет обновлять дескрипторы после вызова vkBindDescriptorSet.
	- Обновление должно быть до отправки командного буфера на ГП (сабмита).
	- Будет использоваться последний установленый дескриптор.
	- Дескрипторы могут обновляться из разных потоков, синхронизация нужна только при одновременном обновлении одного дескриптора.
* `VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT` - требует опцию `descriptorBindingUpdateUnusedWhilePending`. Позволяет обновлять неиспользуемые дескрипторы параллельно с выполнением команд на ГП, которые используют этот дескриптор сет.
	- Дескрипторы могут обновляться из разных потоков, синхронизация нужна только при одновременном обновлении дескриптора.
	- Вместе с `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT` разрешается обновлять дескрипторы, которые не __индексируются динамически__.

### Nonuniform

Однородными являются данные, которые не меняются в пределах вызова команды рисования `vkCmdDraw***`.

Какие данные являются однородными:
* Данные из uniform buffer и push constant.
* `gl_DrawID`.
* Для компьют шейдера: одинаковые значения в пределах воркгруппы, например `gl_WorkGroupID`.

Неоднородные данные:
* `gl_VertexIndex`, `gl_PrimitiveID`, вершинные аттрибуты и тд.
* `gl_LocalInvocationID` и `gl_GlobalInvocationID`.
* `gl_InstanceIndex` на TBR и TBDR архитектурах вершинные и фрагментные шейдеры могут содержать разные инстансы. ([тест](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/perf/TrisPerSubgroup.as))
* `gl_BaseInstance` и `gl_BaseVertex` могут быть однородными по аналогии с `gl_DrawID`, если не используется multi draw.
* `gl_ViewIndex` ???

При использовании `nonuniform()` компилятор может добавить дополнительные инструкции, но если компилятор знает, что переменная только `uniform`, то проигнорирует `nonuniform()` и лишних инструкций не будет.<br/>
Пример [UniqueIDs](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/compute/UniqueIDs-1.as) показывает как компилятор превращает неоднородный доступ к ресурсам в однородный.

Пример [BrokenNonuniform](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/nonuniform/BrokenNonuniform.as) показывает, что будет если не использовать `nonuniform()`.
Почти на всех протестированных ГП драйвер сам обнаруживает неоднородность и `nonuniform()` ни на что не влияет, поэтому такие ошибки сложно отловить. Только на AMD GCN берется один индекс на варп и ошибки сразу проявляются.

Подробнее можно почитать в [Vulkan Samples: descriptor indexing](https://github.com/KhronosGroup/Vulkan-Samples/tree/main/samples/extensions/descriptor_indexing#non-uniform-indexing-enabling-advanced-algorithms).

Также есть параметр `quadDivergentImplicitLod`, который показывает может ли драйвер рассчитать LOD для текстуры, когда индекс меняется в пределах квадрата.

> If the image or sampler object used by an implicit derivative image instruction is not uniform across the quad and quadDivergentImplicitLod is not supported, then the derivative and LOD values are undefined.

Проблем не возникает при одинаковых индексах на треугольник, так как даже на мобилках при объединении нескольких треугольников в один варп, всегда закрашивание идет квадратами.
Для visibility buffer производные и так считаются попиксельно.
Но остаются рельефное текстурирование и постпроцессы с трассировкой, в которых возможно попиксельное вырождение.

Если все же нужно менять индекс попиксельно, то требуется явно посчитать производные:
```
float2 dx = dFdx(uv) * Exp2(bias);
float2 dy = dFdy(uv) * Exp2(bias);
textureGrad( un_Textures[nonuniform(tex_id)], dx, dy );
```

Поддержка `quadDivergentImplicitLod` зависит от производителя, а не версии архитектуры.
Так параметр поддерживается на Adreno, Intel, NVidia, PowerVR и не поддерживается на AMD, Apple, Mali, VideoCore, Maleoon.

Пример [QuadDivergentImplicitLod](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/nonuniform/QuadDivergentImplicitLod.as) покажет появляется ли ошибка, если не использовать `textureGrad()`.
На AMD RX570 разница только в `textureQueryLod().x`.
NVidia, Intel и PowerVR показали небольшое отличие между `texture()` и `textureGrad()`, это может быть связано с меньшей точностью при неявном расчете дериватив.

С Mali оказалось сложнее - `textureQueryLod( nonuniform(...))` не работает вовсе, а `textureGrad( nonuniform(...), dFdx(), dFdy() )` показывает худшую фультрацию вдали. В рекомендациях по оптимизации для Mali даже не советуют использовать `textureGrad` если есть такая возможность.

Более старые Mali Midgard не поддерживают `nonuniform()`, но работают также как более новые Mali Valhall.
На старом Adreno 500 неоднородный доступ не работает вовсе - чтение текстуры возвращает черный цвет.


### Device Address

Расширение `VK_KHR_buffer_device_address` позволяет использовать указатели на память буфера. Адрес получается из `ulong` или `uint2` типа.<br/>
[Пример](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/compute/BufferReference.as) с бинарным деревом.

<details><summary>Поддерживается начиная с:</summary>

* Adreno 600
* AMD GCN1
* Intel gen9 ?
* Mali Bifrost gen1
* Maleoon 9xx
* NVidia Kepler/GTX600 ?
* PowerVR Series 8

</details>


### Descriptor Buffer

Расширение `VK_EXT_descriptor_buffer` упрощает работу с дескрипторами, теперь вместо абстрактных дескриптор сетов и пулов будет буфер, который хранит дескрипторы.
Подробнее в [proposal](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_descriptor_buffer.adoc) и [блоге](https://www.khronos.org/blog/vk-ext-descriptor-buffer).

Обновление данных.<br/>
Теперь обновление дескрипторов аналогично обновлению буфера.
Чтение дескрипторов происходит в шейдере, поэтому обновление должно быть синхронизированно с ними, например:
```
dstStage = VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT
dstAccess = VK_ACCESS_2_DESCRIPTOR_BUFFER_READ_BIT_EXT
```
Аналогично, перед обновлением нужно дождаться пока завершится шейдер.

Так же как с дескриптор сетами все дескрипторы, которые используются динамически должны быть валидны.

В расширении `VK_EXT_robustness2` появилась возможность использовать нулевые дескрипторы, для этого требуется опция `nullDescriptor`.
Говорят, что именно `nullDescriptor` на производительность [не влияет](https://github.com/KhronosGroup/Vulkan-Docs/issues/1971#issuecomment-1308974805).
Тогда как другие опции из robustness расширений могут сильно влиять на производительность.

<details><summary>Поддерживается начиная с</summary>

* Adreno 800/X1 (начиная с 512.800.0 драйвера)
* Adreno Turnip 600 (открытый драйвер)
* AMD GCN4
* Intel Xe-HP
* Intel Xe+LP (Arc 140T)
* Mali Valhall gen3 (начиная с 53.0.0 драйвера)
* NVidia Kepler/GTX7xx

</details>


### Лимиты

Более новые ГП поддерживают сотни текстур на шейдер и часто такие ГП хорошо совместимы с bindless подходом.
Но встречаются еще старые модели, где ограничение в 16-32 текстуры.

<details><summary>Сотни текстур поддерживаются:</summary>

* Adreno 500 (128 текстур, 158 ресурсов всего)
* Adreno 600 (по 524'288 каждого ресурса, 1'572'864 в сумме)
* AMD GCN1 (по 4'294'967'295 каждого ресурса)
* Apple M1 (128 текстур, 159 ресурсов всего) ???
* Intel gen9 (200 текстур, 200 ресурсов всего)
* Intel Xe-HP, Xe+ LP (по 33'554'432 каждого ресурса)
* Mali Bifrost gen1 (256 текстур, 361 ресурсов всего)
* Mali Valhall gen1 (по 500'000 каждого ресурса, 500'000 в сумме)
* Maleoon 9xx (по 500'000 каждого ресурса, 2'000'016 в сумме)
* NVidia Kepler/GTX600 (по 1'048'576 каждого ресурса)
* PowerVR Series 9 (48 текстур, 224 ресурсов всего)
* PowerVR B Series (по 4'294'967'295 каждого ресурса)

</details>


### Descriptor Heap

Дальнейшее развитие `VK_EXT_descriptor_buffer` привело к `VK_EXT_descriptor_heap`, который полностью заменяет descriptor buffer и аналогичен [Resource Heaps из SM 6.6](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_descriptor_heap.adoc#hlsl-mapping).

Больше не используется descriptor set layout, вместо него VkShaderDescriptorSetAndBindingMappingInfoEXT указывается для каждого шейдера отдельно.
Вместо пуш-констант и пуш-дескрипторов используется общий vkCmdPushDataEXT().

Лимиты на ресурсы стали другими, так для буферов они рассчитываются:<br/>
`(maxResourceHeapSize - minResourceHeapReservedRange) / bufferDescriptorSize`.

Ограничения:
* Переключение между descriptor heap может быть очень дорогим, поэтому рекомендуют использовать одну для всего приложения.
* Также дорого переключаться между descriptor heap и другими вариантами дескрипторов: descriptor set, descriptor buffer.
* Командный буфер может использовать только один descriptor heap.

Отсюда можно расчитать максимальное количество ресурсов без потери производительности.

<details><summary>Лимиты:</summary>

* AMD RDNA3+: 134М буферов или 67М текстур.
* NV Turing+: 2М буферов или 1М текстур.

</details>

Для storage buffer лимитов нет, так как можно использовать device address и не занимать дескрипторы.

Упростили и SPIRV: теперь все ресурсы изначально помечены как non-uniform.<br/>
Подробнее в [proposal](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_descriptor_heap.adoc), [docs](https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_descriptor_heap.html), [GLSL](https://github.com/KhronosGroup/GLSL/blob/main/extensions/ext/GLSL_EXT_descriptor_heap.txt).


### Bindless в шейдере

Опция `runtimeDescriptorArray` из расширения `VK_EXT_descriptor_indexing` позволяет не указывать размер массива в шейдере

```
layout(set = 0, binding = 0) uniform sampler2D u_textures[];
layout(set = 0, binding = 1) uniform sampler3D u_volumes[];
```

Но размер задается при создании DescriptorSetLayout, а с флагом `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` возможно создать DescriptorSet, где последний дескриптор может быть переменного размера.

Так как обычно используется только массив 2D текстур, то такого функционала уже достаточно, так же есть возможность создать несколько DescriptorSet с переменным размером последнего массива.

Для флага `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` требуется опция `descriptorBindingVariableDescriptorCount` которую поддерживают почти все ГП.

<details><summary>Не поддерживается:</summary>

* Intel gen8
* Mali Bifrost gen1
* PowerVR 9
* VideoCore 6

</details>

Лимит `maxBoundDescriptorSets` показывает сколько DescriptorSet можно использовать в одном пайплайне.
Минимально - 4, но у более свежих моделей подняли до 7.
Так получаем:
0 - PerPass, Global
1 - PerDraw (также можно заменить на bindless)
2 - bindless-1
3 - bindless-2

<details><summary>Подробнее:</summary>

* Apple: 8
* AMD: 32
* Adreno 500-600: 4
* Adreno 700+: 7
* Intel: 32 (8 на некоторых Mesa драйверах)
* NVIDIA: 32
* Maleoon 910: 6
* Maleoon 920+: 8
* Mali: 4, 7 (новый драйвер с vk 1.3)
* PowerVR 9-B: 4
* PowerVR D+: 32
* Samsung: 32 (копия AMD)
* VideoCore 6+: 16

</details>



## Bindless в Metal

TODO


## Что лучше

__Виртуальные текстуры__:
* Требуют одинаковый формат, как минимум в пределах типа текстуры (albedo, normal, height и тд).
* Используют отступы в 4 пикселя для анизотропной фильтрации, что увеличивает расход памяти.
* Не сложно написать сжатие в BC формат, сильно сложнее ETC и совсем сложно ASTC, поэтому на ПК и Adreno это еще рабочий вариант, а на остальных мобилках - нет, есть один доклад, где сделали сжатие ASTC 6x6 на ГП, как минимум это возможно, но без исходников потребуются месяцы на реализацию.
Но проблема сжатия на мобилках перестает быть проблемой, если не требуется синтез текстур, тогда общий ASTC 4x4 работает аналогично BC форматам, только теряется гибкость в возможности использовать более сжатые 6x6 или 8x8.
* Для совсем слабого железа может быть дорого зависимое чтение текстуры, что решается патчингом на этапе проверки видимости на ГП (если он используется).


__Bindless__ позволяет использовать несколько динамических массивов заданых при создании DescriptorSet и неограниченное количество дескрипторов, размер массива которых задается в DescriptorSetLayout.
По функционалу больше и не требуется, но есть проблемы с производительностью в некоторых случаях:

* Первое это более дорогой неоднородный доступ в пределах варпа.
* Второе это фрагментация памяти - в отличие от виртуальных текстур, где все поделено на квадраты фиксированного размера, тут все текстуры могут быть разного размера *(никто же не будет ограничивать художников)*.
К тому же текстуры загружаются не сразу, а отдельными мипами или диапазонами мип-уровней, каждая такая подгрузка требует выделение новой памяти и копирования из старой.
С другой стороны в этом и преимущество по сравнению с виртуальными текстурами, где если упереться в размер физической текстуры, то новые не загрузятся или будут вытеснять другие и получится, что некоторые текстуры отобразились с меньшей детализацией.


__Атлас из textureArray__ - самый старый способ, который использовался в основном для ландшафтов, но с некоторыми ограничениями подходит и для всей сцены.
Все текстуры должны быть одного размера, они записываются как слои текстурного массива, таким образом не требуется даже динамическая индексация.

Главный недостаток такого подхода - ограниченный размер текстурного массива и невозможность перевыделить память, так как это сразу х2 к расходу памяти, пока идет копирование, а игры обычно уже используют 70-90% памяти.
Также сложно добиться высокой детализации текстур на моделях вблизи, но это решается, если собрать атлас и нарезать его на несколько слоев.

При наличии динамической индексации этот подход становится проще, так как теперь можно создать несколько текстурных массивов разного размера.
А для устранения неоднородности в варпе есть варианты с классификацией тайлов, например для Deferred Texturing и Visibility Buffer техник.
При поддержке разряженой памяти (sparse memory) можно привязывать каждый слой отдельно, что уберет расход памяти на неиспользуемые слои.

В целом, с новыми расширениями даже этот подход работает неплохо.


__Что же лучше__. Для ПК и свежих мобилок bindless подход более удобный.
Виртуальные текстуры позволяют делать синтез текстур, что может быть полезно для ландшафтов и некоторых объектов, а если техника уже реализована, то почему бы не использовать ее для всей сцены?
Тем более во многих движках уже есть поддержка виртуальных текстур с тех времен, когда bindless еще не было, поэтому нет затрат на реализацию техники, нужно только добавлять функционал, пока ограничения и сложные баги не подскажут, что пора что-то менять.


# Тесты производительности

[В отдельном документе](tests/BindlessTests3-ru.md)


# Итоги

Внезапно, только Adreno 660 плохо справился с bindless.
У Intel gen9.5 (UHD620) возникли проблемы с bindless texture + immutable sampler, но на аналогичной по производительности модели Xe-LP (UHD Graphics 730) эту проблему исправили.

Получилось 3 группы:
1. Когда bindless texture + imutable sampler быстрее. Это AMD 780M RADV.
2. Когда bindless texture + bindless sampler быстрее. Это Intel UHD620, PowerVR BXM, Adreno 660, Mali G57.
3. Одинаковая производительность у bindless. Это Intel UHD Graphics 730, Mali G610, AMD 780M PRO и VLK, AMD RX570, NV RTX 2080.

Тесты показали, что `*NonUniformIndexingNative` параметры ни на что не влияет: производительность всегда снижается когда один варп ображается к разным текстурам, а `nonuniform()` нужен только для AMD GCN.

На старых устройствах Mali T830 и Adreno 505 нет поддержки `nonuniform()`, поэтому неоднородный доступ к ресурсам может вызвать неопределенное поведение, а забиндить можно всего 16 текстур.
Зато даже старый Mali T830 корректно работает с неоднородным доступом к текстурам, хоть это и не по стандарту.
