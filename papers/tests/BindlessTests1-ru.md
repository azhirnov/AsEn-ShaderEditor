
1. Nonuniform.<br/>
Разница в производительности между использованием `nonuniform()` и выбором слоя из Texture2DArray.
Чтобы в варп попадали разные индексы используется хэш от `gl_FragCoord` с двумя режимами: квадрат 2х2 и попиксельно.<br/>
Вариант per object больше приближен к реальному использованию, тогда как per quad и per pixel это стресс-тест, но могут возникнуть: per quad для микротреугольников, per pixel в visibility buffer.<br/>

Тест сравнивает производительность разного доступа к ресурсам при низкой нагрузке на другие системы, но не показывает влияния bindless на производительность в целом, поэтому тест будет заменен на новый.

Исходники: [скрипт](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/scripts/perf/NonUniform-Tex.as), [шейдер](https://github.com/azhirnov/AsEn-ShaderEditor/blob/main/src/pipeline_inc/NonUniformTex-shared.as).


**Результаты**
* [AMD RX570](#AMD-RX570)
* [AMD Radeon 780M, AMDPRO](#AMD-Radeon-780M-AMDPRO)
* [AMD Radeon 780M, AMDVLK](#AMD-Radeon-780M-AMDVLK)
* [AMD Radeon 780M, RADV](#AMD-Radeon-780M-RADV)
* [Nvidia RTX 2080](#Nvidia-RTX-2080)
* [ARM Mali G57](#ARM-Mali-G57)
* [ARM Mali G610](#ARM-Mali-G610)
* [Adreno 660](#Adreno-660)
* [PowerVR BXM-8-256](#PowerVR-BXM-8-256)
* [Intel UHD 620](#Intel-UHD-620)
* [Intel N150](#Intel-N150)

## Nvidia RTX 2080

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 1.06     | 2.3       |
| texture & sampler index | 1.01       | 1.06     | 2.3       |

<details><summary><b>Подробные результаты</b></summary>

Тестируется в 8К разрешении, 4К в 4 раза быстрее, значит все упирается в FS.

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 1.55            | 1.59          | 1.71           |
| texture index           | 1.55            | 1.69          | 3.98           |
| texture & sampler index | 1.57            | 1.69          | 3.93           |

</details>

## AMD RX570

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 1.04     | 1.42      |
| texture & sampler index | 1.0        | 1.05     | 1.42      |

<details><summary><b>Подробные результаты</b></summary>

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 6.65            | 6.65          | 8.3            |
| texture index           | 6.65            | 6.94          | 11.8           |
| texture & sampler index | 6.65            | 6.95          | 11.8           |

</details>

## AMD Radeon 780M, AMDPRO

Хоть и нет нативной поддержки неоднородных индексов, но производительность меняется незначительно.

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 0.99     | 1.19      |
| texture & sampler index | 1.0        | 0.99     | 1.19      |

<details><summary><b>Подробные результаты</b></summary>

GPU Clock: 2600MHz

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 9.1             | 10.0          | 10.0           |
| texture index           | 9.1             | 9.9           | 11.9           |
| texture & sampler index | 9.1             | 9.9           | 11.9           |

</details>

## AMD Radeon 780M, AMDVLK

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 0.99     | 1.21      |
| texture & sampler index | 1.0        | 0.99     | 1.21      |

<details><summary><b>Подробные результаты</b></summary>

GPU Clock: 2600MHz

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 9.7             | 10.1          | 10.1           |
| texture index           | 9.7             | 10.0          | 12.2           |
| texture & sampler index | 9.7             | 10.0          | 12.2           |

</details>

## AMD Radeon 780M, RADV

RADV драйвер оказался быстрее других, но bindless сильнее влияет на производительность.

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 1.04     | 1.18      |
| texture & sampler index | 1.0        | 1.07     | 1.26      |

<details><summary><b>Подробные результаты</b></summary>

GPU Clock: 2500MHz

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 5.9             | 7.4           | 8.9            |
| texture index           | 5.9             | 7.7           | 10.5           |
| texture & sampler index | 5.9             | 7.9           | 11.2           |

</details>

## ARM Mali G57

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 1.6      | 2.3       |
| texture & sampler index | 1.0        | 1.64     | 2         |

<details><summary><b>Подробные результаты</b></summary>

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 4.87            | 5.4           | 6.2            |
| texture index           | 4.9             | 8.65          | 14.4           |
| texture & sampler index | 4.9             | 8.85          | 12.4           |

</details>

## ARM Mali G610

Valhall gen3 архитектура уже лучше справляется с bindless по сравнению с gen1.

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 1.27     | 1.52      |
| texture & sampler index | 1.0        | 1.33     | 1.54      |

<details><summary><b>Подробные результаты</b></summary>

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 6.5             | 6.7           | 6.9            |
| texture index           | 6.5             | 8.5           | 10.5           |
| texture & sampler index | 6.5             | 8.9           | 10.6           |

</details>

## Adreno 660

В per object режиме texture layer оказывается в 1.7 раз быстрее, но при переходе к per quad разница минимальна. Скорее всего связано с общей просадкой производительности.

Разница между per object и per quad в 2.1 раза, а между per object и per pixel аж 4.5 раза, что влияет на подход к рисования в целом.
Возможно нужна большая локальность текселей к которым обращается варп, так будет меньше потерь.

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.7        | 1.05     | 1.3       |
| texture & sampler index | 1.7        | 1.04     | 1.28      |

<details><summary><b>Подробные результаты</b></summary>

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 3.8             | 8.1           | 17.2           |
| texture index           | 6.6             | 8.5           | 22.3           |
| texture & sampler index | 6.6             | 8.4           | 22.1           |

</details>

## PowerVR BXM-8-256

| nonuniform              | per object | per quad | per pixel | per pixel 4K |
|-------------------------|------------|----------|-----------|--------------|
| **texture layer**       | 1.0        | 1.0      | 1.0       | 1.0          |
| texture index           | 1.0        | 1.0      | 1.17      | 1.5          |
| texture & sampler index | 1.0        | 1.0      | 1.14      | 1.35         |

<details><summary><b>Подробные результаты</b></summary>

| nonuniform              | per object 2K (ms) | per quad 2K (ms) | per pixel 2K (ms) | per pixel 4K (ms) |
|-------------------------|--------------------|------------------|-------------------|-------------------|
| texture layer           | 3.53               | 3.59             | 3.86              | 10.1              |
| texture index           | 3.53               | 3.59             | 4.5               | 15.1              |
| texture & sampler index | 3.53               | 3.59             | 4.4               | 13.7              |

</details>

## Intel UHD 620

Вариант с bindless texture в разы медленее, скорее всего компилятор сопоставлял immutable sampler с динамической индексацией и получилось очень плохо.

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.0        | 4.9      | 10.8      |
| texture & sampler index | 1.0        | 1.4      | 2.4       |

<details><summary><b>Подробные результаты</b></summary>

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 8.8             | 9.0           | 9.3            |
| texture index           | 8.8             | 44.0          | 100            |
| texture & sampler index | 8.8             | 13.0          | 22.0           |

</details>

## Intel N150

| nonuniform              | per object | per quad | per pixel |
|-------------------------|------------|----------|-----------|
| **texture layer**       | 1.0        | 1.0      | 1.0       |
| texture index           | 1.04       | 1.21     | 1.5       |
| texture & sampler index | 1.04       | 1.21     | 1.5       |

<details><summary><b>Подробные результаты</b></summary>

| nonuniform              | per object (ms) | per quad (ms) | per pixel (ms) |
|-------------------------|-----------------|---------------|----------------|
| texture layer           | 12.0            | 12.4          | 12.7           |
| texture index           | 12.5            | 15.0          | 19.0           |
| texture & sampler index | 12.5            | 15.0          | 19.0           |

</details>
