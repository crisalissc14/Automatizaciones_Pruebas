# GROUNDS — El Hub del Partner

Proyecto Final — Programación Web y Multimedia 2-SIN-4A
Autora: Cristina Colimba

Sitio informativo/interactivo dirigido a partners baristas de una cafetería ficticia (GROUNDS), con noticias, historia, cursos centralizados, tutorial de arte latte, recetario + catas, comunidad y trivia con leaderboard.

## Cómo usarlo

1. Descomprime la carpeta `PROYECTO FINAL MULTIMEDIA Y PROGRAMACION`.
2. Abre `index.html` directamente en el navegador (doble clic). No requiere servidor ni instalación.
3. Necesitas conexión a internet únicamente para cargar las tipografías desde Google Fonts (Newsreader, Archivo, Space Mono), definidas en `css/style.css`. Si no hay internet, el sitio sigue funcionando con las fuentes de reemplazo del sistema.
4. Navega entre las 8 páginas desde el menú superior (o el botón de hamburguesa en móvil).

## Estructura

```
PROYECTO FINAL MULTIMEDIA Y PROGRAMACION/
├── index.html, historia.html, noticias.html, cursos.html,
│   latte-art.html, recetario.html, comunidad.html, trivia.html
├── css/style.css
├── js/
│   ├── nav.js         (menú móvil + año dinámico, en las 8 páginas)
│   ├── contacto.js    (validación del formulario de contacto en index.html)
│   ├── noticias.js    (filtro y buscador de noticias)
│   ├── cursos.js      (buscador en vivo de tabla + tarjetas de cursos)
│   ├── latte-art.js   (tabs, pasos y flipbook)
│   ├── recetario.js   (calculadora de bebidas + hoja de cata)
│   ├── comunidad.js   (tablero de tips + acordeón FAQ)
│   └── trivia.js       (quiz + leaderboard)
└── assets/img/*.svg
```

## Créditos de multimedia

Por una restricción de red del entorno de desarrollo usado para este proyecto, no fue posible descargar fotografías de bancos de imágenes externos (Unsplash, Pexels, Pixabay). En su lugar, **todas las ilustraciones del sitio son piezas vectoriales (SVG) originales**, creadas específicamente para GROUNDS con la paleta de marca del proyecto. Al ser autoría propia, no requieren licencia de terceros.

| Archivo | Fuente | Autor | Licencia |
|---|---|---|---|
| `assets/img/hero-taza.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/historia-ambiente.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/cursos-banner.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/latte-corazon.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/latte-rosetta.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/latte-tulipan.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/pour-frame-1.svg` a `pour-frame-5.svg` | Ilustración propia (secuencia flipbook, alternativa a video) | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/recetario-cata.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/comunidad-tablero.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/trivia-trofeo.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |
| `assets/img/noticias-tablon.svg` | Ilustración propia | Cristina Colimba | Uso libre (autoría propia) |

**Tipografías (Google Fonts):**

| Fuente | Uso | Licencia |
|---|---|---|
| Newsreader | Títulos (display) | SIL Open Font License |
| Archivo | Cuerpo de texto | SIL Open Font License |
| Space Mono | Datos, códigos, timestamps | SIL Open Font License |

El bloque de créditos también está visible en el sitio, al final de `historia.html` (sección `#creditos`), enlazado desde el pie de página de las 8 páginas.

**Nota sobre el video de `latte-art.html`:** por la misma restricción de red no se pudo incorporar un video real libre de derechos. Siguiendo la alternativa que contempla la guía del proyecto, la técnica de vertido se muestra como una secuencia de imágenes ("flipbook") controlada por JavaScript, con reproducción automática y controles de anterior/siguiente.

## Notas de marca

GROUNDS es una marca ficticia creada para este proyecto académico. No usa el logo, la marca registrada ni ningún asset visual de Starbucks; cualquier mención a "la experiencia de un partner barista" es puramente narrativa.
