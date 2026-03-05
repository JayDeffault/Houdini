# Houdini Generator Scripts

Этот репозиторий содержит Python-скрипты для быстрого создания процедурных генераторов в Houdini.

## Что внутри

- `tools/houdini_city_generator.py` — генератор процедурного «городского массива» (башни/здания) на SOP-уровне.

## Быстрый запуск

1. Откройте Houdini.
2. Откройте Python Shell.
3. Выполните:

```python
import sys
sys.path.append('/workspace/Houdini/tools')
import houdini_city_generator as gen
geo = gen.build_city_generator()
```

После этого в `/obj` появится нода `city_generator` с собранной сетью.
