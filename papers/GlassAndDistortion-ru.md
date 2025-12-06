
## Glass

В Doom 2016 стекла рисуются в forward pass. Сначала строятся 5 мипов для сцены за стеклом, потом они размываются в 2 прохода, затем рисуется стекло с декалями.

В шейдере запускается цикл по всем декалям для стекла, рассчитывается финальная гладкость (smoothness) стекла, затем выбирается нужный мип:
* smoothness > 0.975, тогда берется мип 1/2
* smoothness > 0.75, блендится мип 1/2 и 1/4
* smoothness > 0.5, блендится мип 1/4 и 1/8
* smoothness > 0.25, блендится мип 1/8 и 1/16
* в остальных случаях - блендится мип 1/16 и 1/32

![](img/Effect_Glass.jpg)

Детали перед стеклом также размываются, что некорректно. В Doom Eternal это исправили закрасив черным все что перед стеклом.<br/>
![](img/Effect_GlassBug.jpg)

В Cyberpunk не делают размытие из-за чего видна ступенчатость.<br/>
![](img/Effect_Glass2.jpg)

В статье [Refracting Pixels](https://www.froyok.fr/blog/2024-12-refraction/) разбираются подходы из разных игр, все используют аналогичный подход, отличаются только детали.


## Screen-space Distortion

В отдельную текстуру, размера 1/4, рисуется карта искажения для каждого объекта с рефракцией.
Последний проход применяет искажения, добавляет тонемапинг и выводит на экран.

Эффект описан еще в [GPU Gems 2: Generic Refraction Simulation](https://developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-19-generic-refraction-simulation).

![](img/Effect_Distortion.jpg)

[Пример DistortionMap](https://github.com/azhirnov/AsEn-ShaderEditor/tree/main/src/scripts/posteffects/DistortionMap.as).

В статье [Refracting Pixels](https://www.froyok.fr/blog/2024-12-refraction/) также рассматривается и рефракция.
Так в Half-Life 2 и F.E.A.R. каждый прозрачный объект с рефракцией копирует рендер таргет и затем читает из него с учетом рефракции.
Так как все непрозрачные объекты рисуются до прозрачных, то при наложении рефракции, объекты которые расположены перед прозрачным также скопируются и будут использоваться для рефракции, что неправильно.

![](https://www.froyok.fr/blog/2024-12-refraction/resources/example_hl2_steps.webm)

Позднее в играх убрали копирование и искажения накладываются один раз в финальном постпроцессе.

