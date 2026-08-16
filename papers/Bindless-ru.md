Оглавление:
* [В чем преимущество](#В-чем-преимущество)
* [Bindless](#Bindless)
    - [Bindless в Vulkan](#Bindless-в-Vulkan)
    - [Bindless в Metal](#Bindless-в-Metal)
    - [Bindless в DX12](#Bindless-в-DX12)
    - [Bindless в OpenGL](#Bindless-в-OpenGL)
    - [Bindless в движках](#Bindless-в-движках)
    - [Что лучше](#Что-лучше)
* [Тесты производительности](#Тесты-производительности)
* [Итоги](#итоги)


# В чем преимущество

Для начала нужно понять как работает рисование.

В TBR и TBDR архитектурах один варп может закрашивать несколько треугольников, это позволяет уменьшить количество простаивающих потоков (увеличить occupancy).
Но варп может выполнять только один шейдер и один набор состояний.
Так два вызова рисования с одинаковым Pipeline и DescriptorSet могут попасть в один варп в фрагментном шейдере, но если забиндить другой DescriptorSet, то уже нет, а значит в некоторых случаях потребуется в 2 раза больше варпов.
Чем больше плотность геометрии, тем важнее чтобы фрагментные шейдеры полностью заполняли варп.
В этом помогает bindless подход, когда биндится один DescriptorSet, а нужный ресурс выбирается в шейдере по ID.

В дотайловой архитектуре другие особенности.
Часть деталей работы графического пайплайна есть у AMD в статье [Understanding GPU context rolls](https://gpuopen.com/learn/understanding-gpu-context-rolls/).
В железе поддерживается 7 контекстов, которые выполняют команды рисования параллельно, но каждая смена состояний занимает один контекст.
Так bindless вариант выставит состояние один раз и в 6 контекстов запустит параллельное рисование, а выставляя состояния для каждого рисования мы получим 3 состояния и 3 параллельных рисования, то есть в 2 раза меньше работы.<br/>
Это худший случай, когда драйвер не способен оптимизировать переключения текстур/вершинных аттрибутов, но точно случится при смене пайплайна.
А смена пайплайна происходит одинаково как на старом варианте рендера, так и на современном bindless GPU-driven рендере, уменьшить переключения можно за счет ветвления в одном шейдере, вместо переключения на разные.
Либо через разделение шейдера на несколько, примерно как это сделано в TBDR архитектуре, это [отложенное текстурирование](GeometryCulling-ru.md#Deferred-Texturing) и [Visibility buffer](GeometryCulling-ru.md#Visibility-Buffer-VisBuf).

До bindless для аналогичной оптимизации использовали [виртуальные текстуры](VirtualTexturing-ru.md) или атласы и текстурные массивы.

Bindless техники позволяют перенести больше логики на [сторону ГП](#GPUDriven-ru.md), тем самым снизив нагрузку на ЦП.


# Bindless

Идея в том, чтобы забиндить все ресурсы один раз, а в шейдере выбирать нужный буфер и текстуры.

Есть старая модель bindless, когда для каждого рисования задается индекс ресурсов, и более новая, когда индекс ресурса меняется в пределах вызова рисования.

Новая модель bindless позволяет использовать GPU Driven Rendering с сортировкой и отсечением невидимой геометрии на стороне ГП.
Также это позволяет использовать техники типа Deferred Texturing и Visibility Buffer, где чтение текстур идет пост-процессом.


## Производительность

Учитывая архитектуру ГП проблемы с производительностью могут возникнуть при неоднородности внутри варпа, о чем подробнее написано в [Nonuniform главе](#Nonuniform).

Подробнее о замерах производительности написано в [итогах](#Итоги).

### Текстуры

Даже старые мобилки, которые поддерживают Vulkan, хорошо справляются с bindless, но есть нюансы.

Так для Adreno пишут:
> It is recommended to use VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER because of how the Adreno GPU works with Bindless mode. When using a combined image sampler, the GPU can use Bindless mode which is more performant. When using separate samplers, it will fall back to a slower mode. Performance deltas have shown a decrease by 2-5% in the fill rate for separate samplers.

И для Mali:
> A bindless descriptor set will work well with combining resources, allowing indexing into texture and buffer arrays.

То есть сэмплеры надо выставить заранее, нельзя использовать конструкции вида `sampler2D( un_Textures[tex_id], un_Samplers[samp_id] )`.

На AMD:<br/>
Оптимизация в AMD не соответствует текущим реалиям с упором на bindless.
Цитата из статьи [No Graphics API](https://www.sebastianaaltonen.com/blog/no-graphics-api):

> AMDs raw descriptor method loads 256-bit descriptors directly from GPU memory into the compute unit’s scalar registers. Eight subsequent 32-bit scalar registers contain a single descriptor. During the SIMD texture sample instruction, the shader core sends a 256-bit texture descriptor and per-lane UVs to the sampler unit. This provides the sampler all the data it needs to address and load texels without any indirections. The drawback is that the 256-bit descriptor takes a lot of register space and needs to be resent to the sampler for each sample instruction.

> A few years ago it looked like AMDs scalar register based texture descriptors were the winning formula in the long run. Scalar registers are more flexible than a descriptor heap, allowing descriptors to be embedded inside GPU data structures directly. But there’s a downside. Modern GPU workloads such as ray-tracing and deferred texturing (Nanite) lean on non-uniform texture indices. The texture heap index is not uniform over a SIMD wave. A 32-bit heap index is just 4 bytes, we can send it per lane. In contrast, a 256-bit descriptor is 32 bytes. It is not feasible to fetch and send a full 256-bit descriptor per lane.

</details>


### Буферы

UBO оптимизированы под однородный доступ, то есть это одинаковый дескриптор в пределах варпа и чтение по одному смещению, либо по какому-то константному шаблону.
По этой причине динамическая индексация или неоднородный доступ к UBO не быстрее аналогичного подхода с SSBO или [device address](#Device-Address), а у некоторых производителей может быть и медленее.


### Как происходит чтение bindless текстуры

* В шейдере расчитывается индекс дескриптора.
* Отправляется запрос на чтение и варп останавливается.
* ГП по индексу находит дескриптор ресурса. Дескриптор попадает в кэш и последующие чтения будут быстрее.
* Текстурный юнит добавляет в очередь команду чтения текстуры по этому дескриптору.
* Текстурный юнит рассчитывает положения текселей в памяти, читает их, применяет фильтрацию.
* Результат возвращается в шейдер - записывается в регистр.
* Варп возобновляет работу.
* Если индекс дескриптора не однороден в пределах варпа, то на многих ГП (AMD, Intel, ARM) все повторяется заново. На NV этот цикл идет внутри сэмплера и без возвращения в варп.

В случае с рельефным текстурированием, с трассировкой по текстуре глубины, дескриптор не меняется, тут все хорошо.
А вот множество разных персонажей вдали приведут к чтению разных текстур в пределах варпа, что может быть дорого.

Похожим образом читаются виртуальные текстуры:
* Виртуальные UV конвертируется в координаты в таблице адресации.
* Отправляется запрос на чтение текстуры с таблицей адресации и варп останавливается.
* В большинстве случаев значение уже закэшировано в L1, поэтому варп быстро получает результат и возобновляет работу.
* Запрашивается чтение физической текстуры и варп снова останавливается.
* Дескриптор текстуры закэширован, но UV заранее не были известны, поэтому ожидание может быть долгим.

Алгоритм почти совпадает, но разница в двух остановках варпа и размере дескриптора по сравнению с размером UV координаты.
Так размер дескриптора комбинированной текстуры с сэмплером может доходить до 128 байт (32 на AMD), а UV координата занимает всего 4 байта (RG16U формат).

Учитывая что на один материал приходится по 3-4 PBR текстуры, то экономия на памяти дескрипторов становится существенной.
Как написано в цитате выше, на AMD дескриптор занимает 256бит и размещается в скалярных регистрах, то есть 8 регистров уходит на один дескриптор.

Кроме того кэш дескрипторов не такой большой и множественные обращения могут его перегрузить и пойти по более медленному пути.
В отличие от виртуальных текстур тут все менее предсказуемо и сильно зависит от оптимизаций в драйвере и железе.
Но дескрипторы используют свой отдельный кэш, а виртуальные текстуры - общий L1/L2 и под нагрузкой таблица адресации может выгрузиться из L1.


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
Минимальный набор опций, который доступен на большинстве ГП можно посмотреть в [min_nonuniform_desc_idx](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/shared_data/feature_set/parts/min_nonuniform_desc_idx.as).
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
* `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT` - требует опцию `descriptorBindingPartiallyBound`, помечает дескрипторы, которые не используются статически *(подробнее ниже)*.
    - Позволяет хранить невалидные дескрипторы, если к ним нет обращений в шейдере.
    - Без этого флага драйвер считает, что все дескрипторы валидны.
    - Слои валидации не знают по какому индексу читает шейдер, поэтому не работают восе, что опасно сложноуловимыми багами. Намного безопаснее заменить невалидный дескриптор на заглушку.
* `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` - требует опцию `descriptorBindingVariableDescriptorCount`, позволяет сделать последний дескриптор переменного размера. Размер устанавливается при создании набора дескрипторов через структуру `VkDescriptorSetVariableDescriptorCountAllocateInfo`.
    - Слои валидации проверяют, что все дескрипторы в массиве размером `VkDescriptorSetVariableDescriptorCountAllocateInfo::pDescriptorCounts[0]` валидны, а не полный размер массива из DescriptorSetLayout.
* `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` - требует опции `descriptorBindingSampledImageUpdateAfterBind` и другие для каждого типа ресурсов. Позволяет обновлять дескрипторы после вызова vkBindDescriptorSet.
    - Обновление должно быть до отправки командного буфера на ГП (сабмита).
    - Будет использоваться последний установленый дескриптор.
    - Дескрипторы могут обновляться из разных потоков, синхронизация нужна только при одновременном обновлении одного дескриптора.
* `VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT` - требует опцию `descriptorBindingUpdateUnusedWhilePending`. Позволяет обновлять неиспользуемые дескрипторы параллельно с выполнением команд на ГП, которые используют этот набор дескрипторов.
    - Дескрипторы могут обновляться из разных потоков, синхронизация нужна только при одновременном обновлении одного дескриптора.
    - Вместе с `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT` разрешается обновлять дескрипторы, к которым нет обращения в шейдере *(что очень сложно валидировать)*.

Флаг `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` удобно использовать для оптимизации обновления дескрипторов - вместо обновления небольшими частями, их можно накопить и залить за один вызов перед `vkQueueSubmit()`.
Так как дескрипторы часто лежат в device local host visible памяти, то обновление маленькими частями работает неэффективно, к тому же сами дескрипторы могут быть распределены по памяти.

<details><summary>Подробнее про статическое использование</summary>

В документации сказано:

> **Static Use**
>
> A SPIR-V module declares a global object in memory using the OpVariable or OpUntypedVariableKHR instruction, which results in a pointer x to that object. A specific entry point in a SPIR-V module is said to statically use that object if that entry point’s call tree contains a function containing a instruction with x as an id operand. A shader entry point also statically uses any variables explicitly declared in its interface.

> **VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT** specifies that descriptors in this binding that are not dynamically used need not contain valid descriptors at the time the descriptors are consumed. A descriptor is dynamically used if any shader invocation executes an instruction that performs any memory access using the descriptor. If a descriptor is not dynamically used, any resource referenced by the descriptor is not considered to be referenced during command execution.

Вариантов использования 3:
* Статичное - дескриптор объявлен в шейдере и компилятор видит, что к нему может быть обращение.
* Не используется вовсе (не статичное) - можно добавить дескриптор для совместимости с другими шейдерами, но текущий шейдер не будет его использовать.
* Динамическое - происходит обращение к статично используемому дескриптору (sample, load, store, ...).

Примеры:

```glsl
// Константный индекс
out_Color = texture(tex[0], uv);

// Ветвление.
// 'tex[0]' и 'tex[1]' используются статически.
// только один из 'tex[0]' и 'tex[1]' используется динамически, с PARTIALLY_BOUND неиспользуемый дескриптор может быть невалидным.
layout(push_constant) uniform PC { uint mode; } pc;

if ( pc.mode == NORMAL_MAP )
    out_Color *= BumpMapping( texture(tex[0], uv).xyz );
else
    out_Color *= ParallaxMapping( texture(tex[1], uv) );  // rgb - normal, a - height

// Однородный индекс.
// статично используется весь массив 'tex[1024]'
// динамически используется только 'tex[pc.texId]', с PARTIALLY_BOUND только он должен быть валидным.
layout(push_constant) uniform PC { uint texId; } pc;
uniform sampler2D tex[1024];

out_Color = texture(tex[pc.texId], uv);

// Неоднородный индекс
// статично используется весь массив 'tex[1024]'
// динамически используется только 'tex[pc.texId]
in flat uint texId;
uniform sampler2D tex[1024];
uniform Block { bool isValid[1024]; } ub;

if ( ub.isValid[pc.texId] )
    out_Color = texture(tex[nonuniformEXT(pc.texId)], uv);
```

</details>


### Nonuniform

Однородными являются данные, которые не меняются в пределах вызова команды рисования `vkCmdDraw***`.

Какие данные являются однородными:
* Данные из uniform buffer и push constant.
* `gl_DrawID`.
* Для компьют шейдера: одинаковые значения в пределах воркгруппы, например `gl_WorkGroupID`.

Неоднородные данные:
* `gl_VertexIndex`, `gl_PrimitiveID`, `gl_Layer`, вершинные аттрибуты и тд.
* `gl_LocalInvocationID` и `gl_GlobalInvocationID`.
* `gl_InstanceIndex` на TBR и TBDR архитектурах вершинные и фрагментные шейдеры могут содержать разные инстансы. ([тест](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/perf/TrisPerSubgroup.as))
* `gl_BaseInstance` и `gl_BaseVertex` могут быть однородными по аналогии с `gl_DrawID`, если не используется multi draw.
* `gl_ViewIndex` задается в сабпассе, но один сабпас может рисовать сразу в несколько view.
* `gl_Layer` и `gl_ViewIndex`, но на NV и TBDR архитектуре из-за особенностей железа они однородны в пределах варпа в фрагментном шейдере.

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


### Descriptor Update Template

Оптимизация для обновления большого количества дескрипторов.
Расширение `VK_KHR_descriptor_update_template` появилось давно и поддерживается везде, также добавлено в ядро Vk 1.1.

Идея в том, чтобы передать шаблон по которому будут обновляться дескрипторы в последующих вызовах, таким образом драйвер заранее может оптимизировать все конвертации и не тратит время на обработку структуры `VkWriteDescriptorSet`.
В последующих вызовах передается только массив дескрипторов, расположенных по смещениям, указаным в шаблоне.

Выигрышь в производительности будет при множестве `VkWriteDescriptorSet` структур, а обновление массива с одним `VkWriteDescriptorSet`, как это часто бывает в bindless, не даст ускорения.

Пример: [VDescriptorUpdater](https://github.com/azhirnov/as-en/blob/dev/AE/engine/src/graphics_rhi/Vulkan/Descriptors/VDescriptorUpdater.cpp), ветка с `if ( _UseUpdateTemplate() )`.<br/>
Доклад: [Descriptor Update Templates](https://www.khronos.org/assets/uploads/developers/library/2018-vulkan-devday/11-DescriptorUpdateTemplates.pdf)


### Push Descriptor

Расширение `VK_KHR_push_descriptor` появилось давно, но добавили в ядро только в версии 1.4.

Descriptor set layout создается с флагом `VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT`, означающим что для него нельзя создать descriptor set, можно только записать дескрипторы через командный буфер: `vkCmdPushDescriptorSet()`.
Это больше похоже на старый подход из OpenGL.

По производительности могут быть нюансы. Частые смены дескрипторов в стиле OpenGL это медленно.
Драйвера могут поддерживать пуш дескрипторы, но этот путь работает неоптимально, особенно важно тестировать на TBDR, где переключения состояний сильнее влияют на производительность.

На всех устройствах поддерживается не более 32 пуш дескрипторов.

<details><summary>Не поддерживается:</summary>

* Mali Valhall со старым драйвером, добавили начиная с vk 1.3
* Maleoon до 935

</details>


### Проблемы Descriptor Pool

Descriptor Pool создается с фиксированным количеством descriptor set и дескрипторов кадого типа, это проблема, когда используются разные descriptor set с непредсказуемым количеством дескрипторов.
В итоге какой-то из дескрипторов выходит за лимиты и pool не создается, тогда нужно создать второй pool и тд. Остаток дескрипторов оказывается неиспользуемой памятью на ГП.

Причина по которой пул создается с указанием количества каждого типа дескриптора в том, что они все разного размера. Про [RADV драйвер AMD](https://nanokatze.space/blog/vulkan-descriptors/) известно что дескриптор буфера занимает 16 байт, текстура - 32 байта, сэмплер - 16, комбинация текстуры и сэмплера - 64.
Поведение descriptor pool на разном железе можно посмотреть в [отдельном тесте](tests/BindlessTests4-ru.md), хорошо оптимизированные драйвера размещают дескрипторы более компактно.

На некоторых ГП память под дескрипторы ограничена и переключение между descriptor pool может привести к дополнительным синхронизациям.
В Vulkan эти лимиты не доступны пользователям, поэтому находятся случайно при профилировании, только в новых [Descriptor Buffer](#Descriptor-Buffer) и [Descriptor Heap](#Descriptor-Heap) появились эти ограничения - `resourceDescriptorBufferAddressSpaceSize` и `maxResourceHeapSize` лимиты и рекомендация использовать один descriptor buffer/heap на приложение.

Невозможность копировать дескрипторы на стороне ГП, а также оптимизировать копирование дескрипторов со стороны ЦП на ГП.
Для этого добавили расширение `VK_VALVE_mutable_descriptor_type`, а затем `VK_EXT_mutable_descriptor_type`.<br/>
Pool создается с флагом `VK_DESCRIPTOR_POOL_CREATE_HOST_ONLY_BIT_EXT`, что позволяет драйверу лучше оптимизировать обновление дескрипторов.
Затем обновленные дескрипторы копируются в ГП-дескрипторы через `vkUpdateDescriptorSets( .pDescriptorCopies = ... )`.<br/>
Подробнее в [proposal](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_mutable_descriptor_type.adoc).


### Descriptor Buffer

Расширение `VK_EXT_descriptor_buffer` упрощает работу с дескрипторами, теперь вместо абстрактных наборов дескрипторов и пулов будет обычный буфер, который хранит дескрипторы.
Подробнее в [proposal](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_descriptor_buffer.adoc) и [блоге](https://www.khronos.org/blog/vk-ext-descriptor-buffer).

Обновление данных.<br/>
Теперь обновление дескрипторов аналогично обновлению буфера и доступно на стороне GPU.
Чтение дескрипторов происходит в шейдере, поэтому обновление должно быть синхронизированно с ними, например:
```
dstStage = VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT
dstAccess = VK_ACCESS_2_DESCRIPTOR_BUFFER_READ_BIT_EXT
```
Аналогично, перед обновлением нужно дождаться пока завершится шейдер.

По сравнению с `VK_EXT_mutable_descriptor_type` это шаг назад, так как память дескрипторов не может пересекаться.

В расширении `VK_EXT_robustness2` появилась возможность использовать нулевые дескрипторы, для этого требуется опция `nullDescriptor`.
Говорят, что именно `nullDescriptor` на производительность [не влияет](https://github.com/KhronosGroup/Vulkan-Docs/issues/1971#issuecomment-1308974805).
Тогда как другие опции из robustness расширений могут сильно влиять на производительность.

<details><summary>Поддерживается начиная с</summary>

* Adreno 700/X1 (начиная с 512.800.0 драйвера)
* Adreno Turnip 600 (открытый драйвер)
* AMD GCN4
* Intel Xe-HP, Xe+LP (Arc 140T)
* Intel gen 9.5 (Mesa драйвер)
* Mali Valhall gen3 (начиная с 53.0.0 драйвера)
* NVidia Kepler/GTX7xx
* PowerVR D Series

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

Дальнейшее развитие `VK_EXT_descriptor_buffer` привело к `VK_EXT_descriptor_heap`, который полностью заменяет [descriptor buffer](#Descriptor-Buffer) и аналогичен [Resource Heaps из SM 6.6](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_descriptor_heap.adoc#hlsl-mapping).

Больше не используется descriptor set layout, вместо него `VkShaderDescriptorSetAndBindingMappingInfoEXT` указывается для каждого шейдера отдельно.
Есть отдельный режим полного доступа к дескрипторам через `layout(descriptor_heap)`, где pipeline layout не используется вовсе.

Вместо пуш-констант и пуш-дескрипторов используется общий `vkCmdPushDataEXT()`.<br/>
Упростили и SPIRV: теперь все ресурсы изначально помечены как non-uniform.

Лимиты на ресурсы стали другими, так для буферов они рассчитываются как:<br/>
`(maxResourceHeapSize - minResourceHeapReservedRange) / bufferDescriptorSize`.<br/>
Отсюда можно расчитать максимальное количество ресурсов без потери производительности.

<details><summary>Лимиты:</summary>

* AMD RDNA3+: 134М буферов или 67М текстур.
* NV Turing+: 2М буферов или 1М текстур.

</details>

Для storage buffer на самом деле лимитов нет, так как вместо дескрипторов есть [device address](#Device-Address).

Ограничения:
* Переключение между descriptor heap может быть очень дорогим, вплоть до синхронизации с ГП (`vkDeviceWaitIdle()`). Поэтому рекомендуют использовать одну для всего приложения.
* Также дорого переключаться между descriptor heap и другими вариантами дескрипторов: descriptor set, descriptor buffer.
* Командный буфер может использовать только один descriptor heap.

Копирование дескрипторов на строне ГП также поддерживается, а доступ синхронизируется по `VK_ACCESS_2_SAMPLER_HEAP_READ_BIT_EXT` и `VK_ACCESS_2_RESOURCE_HEAP_READ_BIT_EXT`.

Подробнее:
* [Proposal](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_descriptor_heap.adoc)
* [Docs](https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_descriptor_heap.html)
* [Guide](https://docs.vulkan.org/guide/latest/descriptor_heap.html)
* [GLSL](https://github.com/KhronosGroup/GLSL/blob/main/extensions/ext/GLSL_EXT_descriptor_heap.txt)
* [Блог NVIDIA](https://developer.nvidia.com/blog/streamlining-resource-binding-with-end-to-end-support-for-vulkan-descriptor-heaps/), [пример](https://github.com/nvpro-samples/vk_mini_samples/tree/main/samples/descriptor_heap)
* [Vulkan samples](https://github.com/SaschaWillems/Vulkan/blob/master/examples/descriptorheap/descriptorheap.cpp)

#### Поддержка старой биндинг-модели

Descriptor heap дает новые возможности о которых будет расказано в [Bindless в шейдере](#Bindless-в-шейдере), но для поддержки старой модели есть гибкая модель биндингов в рантйме.

Для наилучшей производительности для всего приложения должна использоваться только одна куча (descriptor heap), то есть все вызовы `vkCmdBindResourceHeapEXT()` должны быть с одинаковым `VkBindHeapInfoEXT::heapRange`.

* `VK_DESCRIPTOR_MAPPING_SOURCE_HEAP_WITH_CONSTANT_OFFSET_EXT` - выставляет константные смещения для дескрипторов. Нет дополнительных потерь, когда шейдер читает дескриптор. Но применимо только если использовать один descriptor set на все шейдеры, что чисто bindless подход.
* `VK_DESCRIPTOR_MAPPING_SOURCE_HEAP_WITH_PUSH_INDEX_EXT` - позволяет сдвигать дескрипторы на значение `pushIndex * heapIndexStride`, где heapIndexStride - константа, а pushIndex меняется через `vkCmdPushDataEXT()`, что уже ближе к старой модели дескрипторов.
* `VK_DESCRIPTOR_MAPPING_SOURCE_HEAP_WITH_INDIRECT_INDEX_EXT` - дополнительное смещение для каждого дескриптора записывается в `indirectBuffer` и читается по смещению. Более медленный вариант, так как идет дополнительное чтение памяти.
* `VK_DESCRIPTOR_MAPPING_SOURCE_HEAP_WITH_INDIRECT_INDEX_ARRAY_EXT` - смещение каждого элемента в массиве дескрипторов читается из `indirectBuffer`.
  Этот режим позволяет хранить один уникальный дескриптор в куче (descriptor heap), а ссылаться на него из разных буферов, тогда как все предыдущие варианты предполагают размещать дескрипторы в той же куче, размер которой ограничен, а переключение приводит к потере производительности.
  Только при таком походе получится использовать все 1 млн дескрипторов для текстур на NVIDIA, иначе из-за дублирования в памяти их будет в разы меньше, а нужно еще немного места под буферы.
  Нет смысла использовать такой способ индексации в сочетании со старым bindless подходом, так как получается длинная цепочка: `index in shader -> indirectBuffer -> descriptor in heap`.

### Bindless в шейдере

Опция `runtimeDescriptorArray` из расширения `VK_EXT_descriptor_indexing` позволяет не указывать размер массива в шейдере

```glsl
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
Минимально - 4, но у более свежих моделей подняли до 7. Также некоторые слои валидации резервируют 1 DescriptorSet под свои нужды, например для printf в шейдере.
Так получаем:<br/>
0 - PerPass или Global<br/>
1 - PerDraw (также можно заменить на bindless-0)<br/>
2 - bindless-1<br/>
3 - bindless-2 или резерв для валидации

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
* VideoCore 6+: 16

</details>

С расширением `VK_EXT_descriptor_heap` появилось больше возможностей:

```glsl
layout(descriptor_heap) uniform sampler heapSampler[];
layout(descriptor_heap) uniform texture2D heapTexture2D[];
layout(descriptor_heap) uniform texture3D heapTexture3D[];
layout(descriptor_heap) buffer StorageBufferA {
    vec4 a;
} heapStorageBufferA[];

fragColor = texture(sampler2D(heapTexture2D[27], heapSampler[0]), uv);
```

Теперь размер массива задается динамически во время выполнения C++ кода.
Но недостаток такого подхода - общая память у всех ресурсов, кроме сэмплеров.<br/>
То есть:
```
heapTexture2D[i]      : resourceHeapBase + i * imageDescSize
heapTexture3D[i]      : resourceHeapBase + i * imageDescSize
heapStorageBufferA[i] : resourceHeapBase + i * bufferDescSize
```

По этой причине доступ по неправильному индексу может привести к падению драйвера.
Еще одна сложность - разный размер дескрипторов imageDescSize и bufferDescSize, обычно у текстур они в 2 раза больше, что может вызвать ошибки индексации.

Если нужна индексация внутри шейдера, то требуется передать доступный диапазон для каждого дескриптора:

```glsl
uniform DescriptorRanges
{
    uint heapTexture2D_firstIndex;
    uint heapTexture2D_count;

    uint heapTexture3D_firstIndex;
    uint heapTexture3D_count;

    uint heapStorageBufferA_firstIndex;
    uint heapStorageBufferA_count;
} ub;

uint  tex2d_idx = ...;
ASSERT( tex2d_idx < ub.heapTexture2D_count );
float4  color = texture( heapTexture2D[ub.heapTexture2D_firstIndex + tex2d_idx], heapSampler[samp_id] );
```

Такой способ не совместим с Ycbcr и subsampled (для fragment density map) сэмплерами, а также с input attachment.

Ранее дескрипторы с общей памятью появились в `VK_EXT_mutable_descriptor_type` расширении, но немного в другом виде:

```glsl
layout(set = 0, binding = 0) uniform texture2D Tex2DHeap[];
layout(set = 0, binding = 0) uniform texture3D Tex3DHeap[];
layout(set = 0, binding = 0) uniform textureCube TexCubeHeap[];
layout(set = 0, binding = 0) uniform textureBuffer TexelBufferHeap[];
layout(set = 0, binding = 0) uniform image2D RWTex2DHeap[];
layout(set = 0, binding = 0) uniform image3D RWTex3DHeap[];
layout(set = 0, binding = 0) uniform imageBuffer StorageTexelBufferHeap[];
layout(set = 0, binding = 0) uniform CBVHeap { vec4 data[4096]; } CBVHeap[];
...

// и отдельно сэмплеры
layout(set = 0, binding = 1) uniform sampler SamplerHeap[];
```

Чтобы включить такой режим нужно добавить `VkMutableDescriptorTypeCreateInfoEXT` к `VkDescriptorSetLayoutCreateInfo`.
Конкретный тип дескриптора определяется при его обновлении через `vkUpdateDescriptorSets()`, так же как в descriptor heap, чтение дескриптора с неправильным типом это неопределенное поведение и может привести к падению драйвера.<br/>
Подробнее в [примерах к proposal](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/proposals/VK_EXT_mutable_descriptor_type.adoc#4-examples).

Стоит ли использовать `VK_EXT_descriptor_heap` и `VK_EXT_mutable_descriptor_type` с небезопасными типами дескрипторов? В первой итерации перехода на bindless не стоит.


### Обновление дескрипторов

Обычно есть 3 типа наборов дескрипторов по частоте переключения: PerPass, Material, PerDraw.<br/>
PerDraw обычно хранит только трансформации, поэтому заменяется на пуш константу с индексом в массиве трансформаций.<br/>
Material для bindless также заменяется на один большой набор дескрипторов на всю сцену, получаем BindlessMaterials дескрипторы.<br/>
PerPass обновляется только при смене текстур, чаще всего при изменении разрешения экрана или формата, или при изменении конфигурации эффекта/рендера.

PerPass дескрипторы из-за редкости обновления можно пересоздавать:
```
DescriptorSet  perPassDS;

if ( changed )
{
    DelayedRelease( perPassDS );
    perPassDS = AllocDescSet();
}
BindDescriptorSet( perPassDS );
```

С материалами сложнее, подгрузка ресурсов может идти постоянно, при быстром перемещении например, поэтому нужна привязка к кадрам:
```
DescriptorSet  bindlessMaterialsDS[FrameCount];
...
UpdateDescriptors(bindlessMaterialsDS[frameId]);
BindDescriptorSet(bindlessMaterialsDS[frameId]);
```

Флаг `VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT` здесь бесполезен, так как пересоздавать набор дескрипторов под новый размер каждый кадр будет совсем неоптимально.<br/>
Флаги `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT` и `VK_DESCRIPTOR_BINDING_UPDATE_UNUSED_WHILE_PENDING_BIT` полезнее для bindless, но легко приводят к случайному обращению к невалидному дескриптору или к гонке данных, поэтому лучше не использовать.

Расширение `VK_EXT_mutable_descriptor_type` вместе с флагом `VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` позволит обновить множество дескрипторов в host-памяти, а затем залить их на ГП.
Таким образом достаточно двойной буферизации для BindlessMaterials.

В `VK_EXT_descriptor_buffer` и `VK_EXT_descriptor_heap` появилась возможность копировать дескрипторы на стороне ГП, теперь для BindlessMaterials не нужна буферизация вовсе.
Теперь буферизация будет в промежуточном буфере на стороне ЦП.


### Итог по Vulkan

Получаем модели:
* vk 1.0 descriptor pool без bindless.
* descriptor pool с dynamic indexing - первый вариант bindless.
* descriptor pool с update template - оптимизация для ЦП, но не ускоряет массивы (bindless).
* descriptor pool с mutable descriptor type - bindless как в DX12, но сделано как костыль для эмуляции.
* push descriptor - быстрое обновление до 32 дескрипторов, не годится для bindless.
* descriptor buffer - лучше совместимость с DX12, ближе к железу. API не совместим с предыдущими.
* descriptor heap - bindless как в DX12, третья попытка. Отказались от PipelineLayout. API не совместим с предыдущими.


## Bindless в Metal

Без Argument buffer количество ресурсов на пайплайн ограничено:
* 31 буфер
* 31-128 текстур, в зависимости от железа
* 16 сэмплеров

В MSL компилятор сам обрабатывает неоднородные индексы, наоборот тут есть `uniform<T>` шаблоны, которые явно указывают на однородность данных.

### Argument buffer tier 1

Поддерживается на старом железе, до A12 включительно. Более новое железо уже поддерживает Tier 2.
Argument buffer добавляет один уровень перенаправления чтобы прочитать дескриптор, что незначительно влияет на производительность.

Ограничения:
* Фиксированный размер массивов.
* Нет динамической индексации, только dynamicaly uniform индексация.

Metal может выгружать данные из памяти ГП, а также автоматически вставляет синхронизации, но при использовании Argument buffer это нужно делать явно.
Методы `useResource` и `useResources` требует явно указывать список ресурсов, что более затратно.
Методы `useHeap` и `useHeaps` принимают только кусок памяти на котором созданы ресурсы, внутри драйвер обходит все ресурсы и выполняет синхронизации, что более оптимально для ЦП.

Ссылки:
* [Improving CPU performance by using argument buffers](https://developer.apple.com/documentation/metal/improving-cpu-performance-by-using-argument-buffers?language=objc)
* [Managing groups of resources with argument buffers](https://developer.apple.com/documentation/metal/managing-groups-of-resources-with-argument-buffers?language=objc)
* [Tracking the resource residency of argument buffers](https://developer.apple.com/documentation/metal/tracking-the-resource-residency-of-argument-buffers?language=objc)


### Argument buffer tier 2

Поддерживается начиная с A13 и M1.

Лимиты для A13:
* Нет ограничений на количество буферов.
* 1М текстур на шейдер.
* 128 сэмплеров на шейдер.

На более новых моделях только увеличивается количество сэмплеров.

Ссылки:
* [Explore bindless rendering in Metal](https://developer.apple.com/videos/play/wwdc2021/10286/)
* [Go bindless with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10101/)
* [Rendering terrain dynamically with argument buffers](https://developer.apple.com/documentation/metal/rendering-terrain-dynamically-with-argument-buffers?language=objc)
* [Encoding argument buffers on the GPU](https://developer.apple.com/documentation/Metal/encoding-argument-buffers-on-the-gpu?language=objc)


## Bindless в DX12

Неоднородный доступ к ресурсам также нужно оборачивать в `NonUniformResourceIndex(idx)`.

Абстракция над дескрипторами в DX12 оказалась более удачной, чем в Vulkan и не потерпела существенных изменений.

### Descriptor Table

Первая версия. Несмотря на то, что descriptor heap уже был, в шейдере доступ к дескрипторам осуществлялся через прослойку в виде descriptor table, где указывались смещения на дескрипторы или массивы дескрипторов.

### Dynamic Resources

В SM 6.6 добавили прямой доступ к descriptor heap из шейдера.

Пример
```hlsl
Texture2D tex = ResourceDescriptorHeap[index];
SamplerState samp = SamplerDescriptorHeap[samplerIndex];

float4 color = tex.Sample(samp, uv);
```


## Bindless в OpenGL

OpenGL не поддерживает динамическую индексацию ресурсов, в более поздних версиях разрешили dynamicaly uniform индексацию, когда индекс задается через юниформы или юниформ буфер.

Но есть расширение [GL_ARB_bindless_texture](https://registry.khronos.org/OpenGL/extensions/ARB/ARB_bindless_texture.txt), которое добавляет функционал dynamic indexing и non-uniform.
Так как OpenGL позволяет драйверу выгружать данные из памяти ГП, то для каждой текстуры придется вызвать `glMakeImageHandleResidentARB()` перед использованием в шейдере.


## Bindless в движках

Например, в **O3DE** ресурс может быть зарегистрирован в BindlessManager, далее в шейдер передается только его индекс и используется, как это описано в [Bindless в шейдере](#Bindless-в-шейдере).
Такой подход совместим и с DX12, Metal argument buffer и со всеми тремя bindless моделями в Vulkan. При этом в движке используется обычная descriptor set модель с dynamic indexing, никаких новых фич еще не добавили.

То есть все задизайнено под SM 6.6 descriptor heap модель, а где это не поддерживается работает эмуляция через большие массивы.
Недостаток такого подхода - низкая безопасность, в случае неправильного индекса чтение происходит дескриптора не того типа или уже удаленного ресурса, отлавливать такие ошибки очень сложно.

В движках idTech до поддержки RTX делали небольшие массивы текстур и группировали выызовы рисования. Помимо лучшей безопасности это позволяет поддерживать старые Intel с лимитами в 256 текстур.
Это удобно и безопасно для Forward+ и Deferred техник, но плохо совместимо с Visibility buffer и RTX, где нужны все текстуры сразу, либо придется делать классификацию и несколько проходов текстурирования.

Больше всего расширений поддерживает **dxvk**, для которого изначально и добавлялось `VK_VALVE_mutable_descriptor_type` расширение, а затем и все остальные.

В **AsEn** пока нет bindless обертки.
Но удобнее всего добавить bindless в виде одного большого набора дескрипторов, где индекс в массиве совпадает с индексом `ImageViewID` в пуле ресурсов.


## Что лучше

__Виртуальные текстуры__:
* Требуют одинаковый формат, как минимум в пределах типа текстуры (albedo, normal, height и тд).
* Используют отступы в 4 пикселя для анизотропной фильтрации, что увеличивает расход памяти.
* Не сложно написать сжатие в BC формат, сильно сложнее ETC и совсем сложно ASTC, поэтому на ПК и Adreno это еще рабочий вариант, а на остальных мобилках - нет, есть один доклад, где сделали сжатие ASTC 6x6 на ГП, как минимум это возможно, но без исходников потребуются месяцы на реализацию.
Но проблема сжатия на мобилках перестает быть проблемой, если не требуется синтез текстур, тогда общий ASTC 4x4 работает аналогично BC форматам, только теряется гибкость в возможности использовать более сжатые 6x6 или 8x8.
* Для совсем слабого железа может быть дорого зависимое чтение текстуры, что решается патчингом на этапе проверки видимости на ГП (если он используется).
* Есть сложности с трассировкой лучей, где в отражения попадают объект за пределами видимости и нужен новый механизм запросов на подгрузку текстур.


__Bindless__ позволяет использовать несколько динамических массивов заданых при создании DescriptorSet и неограниченное количество дескрипторов, размер массива которых задается в DescriptorSetLayout.
По функционалу больше и не требуется, но есть проблемы с производительностью и безопасностью в некоторых случаях:

* Более дорогой неоднородный доступ в пределах варпа.
* Фрагментация памяти - в отличие от виртуальных текстур, где все поделено на квадраты фиксированного размера, тут текстуры могут быть разного размера *(никто же не будет ограничивать художников)*.
К тому же текстуры загружаются не сразу, а отдельными мипами или диапазонами мип-уровней, каждая такая подгрузка требует выделение новой памяти и копирования из старой.
С другой стороны в этом и преимущество по сравнению с виртуальными текстурами, где если упереться в размер физической текстуры, то новые не загрузятся или будут вытеснять другие и получится, что некоторые текстуры отобразились с меньшей детализацией, чем возможно.
* Как и в виртуальных текстурах тут тоже бывает косвенное обращение. Можно посмотреть на descriptor heap в Vulkan с `VK_DESCRIPTOR_MAPPING_SOURCE_HEAP_WITH_INDIRECT_INDEX_ARRAY_EXT` режимом биндига, где косвенных обращений больше всего. Но вариант с прямым доступом к куче дескрипторов конечно же выигрывает по производительности.
* Падения драйвера при доступе к дескрипторам по индексу: выход за пределы массива, не инициализированный или протухший дескриптор, неправильный тип дескриптора и тд.


__Атлас из textureArray__ - самый старый способ, который использовался в основном для ландшафтов, но с некоторыми ограничениями подходит и для всей сцены.
Все текстуры должны быть одного размера, они записываются как слои текстурного массива, таким образом не требуется даже динамическая индексация.

Главный недостаток такого подхода - ограниченный размер текстурного массива и невозможность перевыделить память, так как это сразу х2 к расходу памяти, пока идет копирование, а игры обычно уже используют 70-90% памяти.
Также сложно добиться высокой детализации текстур на моделях вблизи, но это решается, если собрать атлас и нарезать его на несколько слоев.

При наличии динамической индексации этот подход становится проще, так как теперь можно создать несколько текстурных массивов разного размера.
А для устранения неоднородности в варпе есть варианты с классификацией тайлов, например для Deferred Texturing и Visibility Buffer техник.
При поддержке разряженой памяти (sparse memory) можно привязывать каждый слой отдельно, что уберет расход памяти на неиспользуемые слои.
Из минусов - получаем 4D индексацию: номер текстуры, номер слоя и UV. Способ работает только для 2D текстур, для 3D уже нет текстурного массива.

В целом, с новыми расширениями даже этот подход работает неплохо.


__Что же лучше__. Для ПК и свежих мобилок bindless подход более удобный.
Виртуальные текстуры позволяют делать синтез текстур, что может быть полезно для ландшафтов и некоторых объектов, а если техника уже реализована, то почему бы не использовать ее для всей сцены?
Тем более во многих движках уже есть поддержка виртуальных текстур с тех времен, когда bindless еще не было, поэтому нет затрат на реализацию техники, нужно только добавлять функционал, пока ограничения и сложные баги не подскажут, что пора что-то менять.


# Тесты производительности

В отдельном документе:

* [Старые, самые полные](tests/BindlessTests3-ru.md)
* [Старые, больше тестов, но не полные](tests/BindlessTests3-ru.md)
* [Новые (в процессе)](tests/BindlessTests3-ru.md)
* [Тесты особенностей драйверов](tests/BindlessTests4-ru.md)


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
