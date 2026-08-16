
1.1. Nonuniform stress test v2<br/>
Разница в производительности между использованием `nonuniform()` и выбором слоя из Texture2DArray.
Чтобы в варп попадали разные индексы используется хэш от `gl_FragCoord` с двумя режимами: квадрат 2х2 и попиксельно.<br/>
Вариант per object больше приближен к реальному использованию, тогда как per quad и per pixel это стресс-тест, но могут возникнуть: per quad для микротреугольников, per pixel в visibility buffer.<br/>
Тест сравнивает производительность разного доступа к ресурсам при низкой нагрузке на другие системы, но не показывает влияния bindless на производительность в целом.<br/>
Исходники: [скрипт](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/nonuniform/NonUniform-Stress.as), [шейдер](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/pipeline_inc/NonUniform-Stress-shared.as).

1.2. Nonuniform with depth pre-pass<br/>
Сделаны примитивные объекты в виде повернутых прямоугольников, вытянутые формы приводят к тому, что больше треугольников попадают в варп и сильнее проявляется неоднородность индексов.
Показывает разницу в производительности между использованием `nonuniform()` и выбором слоя из Texture2DArray.
Можно менять детализацию текстур, чтобы определить насколько bindless влияет на производительность при нормальной нагрузке на память и при пониженой, когда читаются нижние мип-уровни.<br/>
Исходники: [скрипт](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/nonuniform/NonUniform-DPP.as), [шейдер](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/pipeline_inc/NonUniform-shared.as).

1.3. Nonuniform with visibility buffer<br/>
Аналогично depth pre-pass, но вызывается меньше фрагментных шейдеров и больше уникальных индексов в варпе.
На слабом железе сильно нагружается ALU из-за чего нагрузка на текстуры оказалась минимальной.<br/>
Исходники: [скрипт](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/nonuniform/NonUniform-VB.as), [шейдер](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/pipeline_inc/NonUniform-VB-shared.as).

Все три теста оказались не достаточно информативными, хватило данных чтобы разбить ГП по группам, но сложно оценить как влияет увеличение общего количества текстур, увеличение количества чтений текстур для PBR, parallax mapping, ландшафта, где нагрузка увеличивается в 4 раза.


**Результаты**
* [AMD RX570](#AMD-RX570)
* [Nvidia RTX 2080](#Nvidia-RTX-2080)
* [ARM Mali G57](#ARM-Mali-G57)
* [Apple M1](#Apple-M1)
* [Intel UHD 620](#Intel-UHD-620)
* [Intel N150](#Intel-N150)

## Nvidia RTX 2080

**Nonuniform, depth pre-pass**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.0        | 1.014    | 1.13     | 1.99      |
| texture & sampler index | 1.0        | 1.018    | 1.11     | 1.97      |

**Nonuniform, visibility buffer**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.007      | 1.007    | 1.02     | 1.43      |
| texture & sampler index | 1.007      | 1.007    | 1.03     | 1.41      |

<details><summary><b>Подробные результаты</b></summary>

**Nonuniform stress test v2**

Scale=0.9, Dim=8K, ObjCount=4K, TexBias=4

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 2.25            | 2.27          | 2.27          | 2.31           |
| texture index           | 2.25            | 2.27          | 2.30          | 4.0            |
| texture & sampler index | 2.25            | 2.27          | 2.30          | 3.95           |

**Nonuniform, depth pre-pass**

dpp = 0.5ms,
Scale=0.2, Dim=8K, ObjCount=32K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 2.17            | 2.2           | 2.24          | 4.34           |
| texture index           | 2.17            | 2.23          | 2.52          | 8.64           |
| texture & sampler index | 2.17            | 2.24          | 2.48          | 8.56           |

**Nonuniform, visibility buffer**

visibility buffer build = 1.2ms<br/>
visibility buffer FS overhead = 1.26ms<br/>
Scale=0.2, Dim=8K, ObjCount=32K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 1.38            | 1.40          | 1.42          | 1.55           |
| texture index           | 1.39            | 1.41          | 1.45          | 2.22           |
| texture & sampler index | 1.39            | 1.41          | 1.46          | 2.18           |

</details>


## AMD RX570

Из-за бага в драйвере nonuniform работает через раз. Первые тесты делались на текстурах с низким разрешением (64х64) и видимо они попадали в кэш, поэтому проблема не проявлялась и разница в производительности оказалась небольшой.
В новом тесте используются текстуры 1024х1024 и это приводит к некорректным данным при чтении, а также потере производительности.
Когда драйвер работал корректно вариант с visibility buffer оказался намного быстрее с bindless подходом.

**Nonuniform, depth pre-pass**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 2.24       | 2.03     | 2.47     | 2.52      |
| texture & sampler index | 2.24       | 2.03     | 2.47     | 2.52      |

**Nonuniform, visibility buffer**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.017      | 1.013    | 1.21     | 1.79      |
| texture & sampler index | 1.026      | 1.022    | 1.21     | 1.8       |

<details><summary><b>Подробные результаты</b></summary>

**Nonuniform, depth pre-pass**

dpp = 0.4ms,<br/>
Scale=0.6, Dim=2K, ObjCount=4K<br/>
**Texture bias doesn't work with nonuniform! Nonuniform access sometimes has flickering!**

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 2.4             | 2.4           | 2.4           | 2.4            |
| texture index           | 19              | 19.5          | 19.5          | 19.5           |
| texture & sampler index | 19              | 19.5          | 19.5          | 19.5           |

**Nonuniform, visibility buffer**

visibility buffer build = 1.15ms<br/>
visibility buffer FS overhead = 0.52ms<br/>
Scale=0.6, Dim=2K, ObjCount=4K, TexDim=1024<br/>
**Texture bias doesn't work with nonuniform! Nonuniform access sometimes has flickering!**

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 1.45            | 1.6           | 1.54          | 1.52           |
| texture index           | 3.25            | 3.25          | 3.8           | 3.83           |
| texture & sampler index | 3.25            | 3.25          | 3.8           | 3.83           |

**Nonuniform, visibility buffer v2**

visibility buffer build = 3.8ms<br/>
visibility buffer FS overhead ms<br/>
Scale=1.0, Dim=4K, ObjCount=4K, TexDim=64<br/>
**Textures stored in cache and nonuniform access is fast and correct.**

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 5.74            | 6.35          | 6.13          | 6.24           |
| texture index           | 5.84            | 6.43          | 7.40          | 11.2           |
| texture & sampler index | 5.89            | 6.49          | 7.41          | 11.25          |

</details>


## ARM Mali G57

**Nonuniform, depth pre-pass**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.034      | 0.94     | 1.35     | 2.68      |
| texture & sampler index | 1.034      | 0.92     | 1.39     | 2.6       |

<details><summary><b>Подробные результаты</b></summary>

**Nonuniform, depth pre-pass**

dpp = 8.1ms,<br/>
Scale=1, Dim=4K, ObjCount=4K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 8.8             | 16            | 17.6          | 30.8           |
| texture index           | 9.1             | 15            | 23.8          | 82.4           |
| texture & sampler index | 9.1             | 14.7          | 24.4          | 80             |

**Nonuniform, visibility buffer**

Visibility buffer resolve takes 90% of time.

</details>


## Apple M1

**Nonuniform, depth pre-pass**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.03       | 0.98     | 0.99     | 0.99      |
| texture & sampler index | 1.06       | 0.96     | 0.95     | 0.96      |

**Nonuniform, visibility buffer**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.06       | 0.99     | 1.005    | 1.07      |
| texture & sampler index | 1.09       | 1.005    | 1.016    | 1.07      |

<details><summary><b>Подробные результаты</b></summary>

**Nonuniform, depth pre-pass**

dpp = 1.8ms,<br/>
Scale=0.6, Dim=8K, ObjCount=4K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 1.6             | 2.7           | 4.4           | 7.3            |
| texture index           | 1.65            | 2.65          | 4.35          | 7.2            |
| texture & sampler index | 1.7             | 2.6           | 4.2           | 7.0            |

**Nonuniform, visibility buffer**

visibility buffer build = 1.2ms<br/>
visibility buffer FS overhead = 1.5ms<br/>
Scale=0.6, Dim=4K, ObjCount=4K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 1.6             | 1.84          | 1.92          | 2.0            |
| texture index           | 1.69            | 1.82          | 1.93          | 2.14           |
| texture & sampler index | 1.74            | 1.85          | 1.95          | 2.14           |

</details>


## Intel UHD 620

**Nonuniform, depth pre-pass**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.0        | 2.2      | 7.5      | 9.7       |
| texture & sampler index | 1.03       | 1.0      | 1.86     | 1.94      |

**Nonuniform, visibility buffer**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.14       | 1.08     | 3.7      | 8.7       |
| texture & sampler index | 1.14       | 1.04     | 1.57     | 2.6       |

<details><summary><b>Подробные результаты</b></summary>

**Nonuniform, depth pre-pass**

dpp = 0.6ms,<br/>
Scale=0.6, Dim=2K, ObjCount=4K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 1.90            | 2.3           | 3.5           | 6.5            |
| texture index           | 1.90            | 5.0           | 26.1          | 63             |
| texture & sampler index | 1.96            | 2.3           | 6.5           | 12.6           |

**Nonuniform, visibility buffer**

visibility buffer build = 0.97ms<br/>
visibility buffer FS overhead = 0.6ms<br/>
Scale=0.6, Dim=2K, ObjCount=4K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 2.55            | 2.6           | 2.7           | 2.9            |
| texture index           | 2.9             | 2.8           | 10.1          | 25.2           |
| texture & sampler index | 2.9             | 2.7           | 4.25          | 7.6            |

</details>


## Intel N150

**Nonuniform, depth pre-pass**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.19       | 0.82     | 1.48     | 1.6       |
| texture & sampler index | 1.19       | 0.82     | 1.48     | 1.6       |

**Nonuniform, visibility buffer**

| nonuniform              | per object | per warp | per quad | per pixel |
|-------------------------|------------|----------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0      | 1.0       |
| texture index           | 1.17       | 1.02     | 1.56     | 2.4       |
| texture & sampler index | 1.15       | 1.02     | 1.56     | 2.4       |

<details><summary><b>Подробные результаты</b></summary>

**Nonuniform, depth pre-pass**

Scale=0.6, ObjCount=4K, Dim=4K, dpp=0.52ms

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 2.7             | 4.4           | 5.6           | 10.9           |
| texture index           | 3.2             | 3.6           | 8.3           | 17.6           |
| texture & sampler index | 3.2             | 3.6           | 8.3           | 17.6           |

**Nonuniform, visibility buffer**

visibility buffer build 0.8= ms<br/>
visibility buffer FS overhead = ms<br/>
Scale=0.6, ObjCount=4K, Dim=4K

| nonuniform              | per object (ms) | per warp (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|---------------|----------------|
| texture layer           | 2.52            | 2.6           | 2.7           | 3.2            |
| texture index           | 2.95            | 2.65          | 4.2           | 7.7            |
| texture & sampler index | 2.91            | 2.65          | 4.2           | 7.7            |

</details>
