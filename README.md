# Houdini Generator Scripts

Этот репозиторий содержит Python-скрипты для быстрого создания процедурных генераторов в Houdini.

## Что внутри

- `tools/houdini_city_generator.py` — генератор **дорог и перекрёстков** на SOP-уровне.

## Быстрый запуск

1. Откройте Houdini.
2. Откройте Python Shell.
3. Выполните:

```python
import sys
sys.path.append('/workspace/Houdini/tools')
import houdini_city_generator as gen
geo = gen.build_road_generator()
```

После этого в `/obj` появится нода `road_intersection_generator`.

## Параметры

- `City Size` — размер области генерации.
- `Street Count` — количество горизонтальных дорог.
- `Avenue Count` — количество вертикальных дорог.
- `Road Width` — ширина дорожного полотна.
- `Intersection Scale` — множитель радиуса площадок перекрёстков.
