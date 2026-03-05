# Houdini Road & Intersection Generator

Это большой production-style генератор дорог и перекрёстков для Houdini.

## Что внутри

- `tools/houdini_city_generator.py` — модуль на 1000+ строк с:
  - профилями генерации (`micro`, `balanced`, `dense_core`, `suburban`, `mega_grid`),
  - модульным конструктором нод-сети,
  - генерацией осей дорог, перекрёстков, полотна, разметки, тротуаров, островков,
  - вспомогательными API-методами для пайплайна.

## Быстрый запуск

```python
import sys
sys.path.append('/workspace/Houdini/tools')
import houdini_city_generator as gen

geo = gen.build_road_generator(profile='balanced')
```

## Дополнительно

- Список профилей:

```python
gen.list_profiles()
```

- Запуск через wrapper:

```python
geo = gen.build_road_generator_with_profile(profile='dense_core')
```
