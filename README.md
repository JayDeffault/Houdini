# Houdini Curve-Based Road Generator

Генератор рассчитан на сценарий: **ты рисуешь curve-ы дорог**, а скрипт автоматически
собирает дорожную полигональную геометрию и перекрёстки.

## Что умеет

- Принимает входные curves из указанного SOP пути (`input_sop_path`).
- Обрабатывает пересечения через `fuse` + анализ valence точек.
- Генерирует полигональные дороги (`polyexpand2d`).
- Добавляет площадки перекрёстков (intersection pads).
- Поддерживает отдельную ширину для групп дорог:
  - `highway`
  - `primary`
  - `secondary`
  - `local`

## Атрибуты на входных кривых

Желателен primitive string-атрибут `road_group`.

Примеры значений:
- `highway`
- `primary`
- `secondary`
- `local`

Если атрибут отсутствует, дорога считается `local`.

## Быстрый запуск в Houdini Python Shell

```python
import sys
sys.path.append('/workspace/Houdini/tools')
import houdini_city_generator as gen

geo = gen.build_curve_road_generator('/obj/curves/OUT_CURVES')
```

## Управление шириной

На созданной GEO-ноде появятся параметры:
- `width_highway`
- `width_primary`
- `width_secondary`
- `width_local`

Также есть `intersection_scale`, `fuse_distance`, `road_y_offset`.
