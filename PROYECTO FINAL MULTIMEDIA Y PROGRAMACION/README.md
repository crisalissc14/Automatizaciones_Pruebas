# GROUNDS — El Hub del Partner

**Universidad Internacional del Ecuador (UIDE)**
Materia: Multimedia y Programación Web
Estudiante: Cristina Colimba Ramos
Proyecto Final — 2026

Sitio informativo/interactivo dirigido a partners baristas de una cafetería ficticia (GROUNDS), con noticias, historia, cursos centralizados, tutorial de arte latte, recetario + catas, comunidad y trivia con leaderboard.

## Cómo usarlo

1. Descomprime la carpeta `PF_ColimbaRamosCristina`.
2. Abre `index.html` directamente en el navegador (doble clic). No requiere servidor ni instalación.
3. Necesitas conexión a internet únicamente para cargar las tipografías desde Google Fonts (Poppins, Inter, Space Mono), definidas en `css/style.css`. Si no hay internet, el sitio sigue funcionando con las fuentes de reemplazo del sistema.
4. Navega entre las 8 páginas desde el menú superior (o el botón de hamburguesa en móvil).

## Estructura
PROYECTO FINAL MULTIMEDIA Y PROGRAMACION/
├── index.html, historia.html, noticias.html, cursos.html,
│ latte-art.html, recetario.html, comunidad.html, trivia.html
├── css/style.css
├── js/
│ ├── nav.js (menú móvil + año dinámico, en las 8 páginas)
│ ├── carousel.js (carrusel reutilizable con autoplay y video)
│ ├── contacto.js (validación del formulario de contacto en index.html)
│ ├── noticias.js (filtro y buscador de noticias)
│ ├── cursos.js (buscador en vivo de tabla + tarjetas de cursos)
│ ├── latte-art.js (tabs, pasos y flipbook)
│ ├── recetario.js (calculadora de bebidas + hoja de cata)
│ ├── comunidad.js (tablero de tips + acordeón FAQ)
│ └── trivia.js (quiz + leaderboard)
├── assets/img/*.svg, *.jpg, .png
└── assets/video/.mp4

## Cumplimiento de requisitos del proyecto final
- **8 páginas HTML completas** (se pide un mínimo de 4-5), todas con `<!DOCTYPE html>`, `lang="es"`, un único `<h1>` por página y validadas estructuralmente.
- **CSS**: sistema de diseño centralizado en `css/style.css` mediante variables (`:root`), tipografía, componentes reutilizables (tarjetas, tickets, carrusel, acordeón, tabs, tabla, formularios) y diseño responsive (breakpoints en 375px, 768px y 1280px).
- **JavaScript**: interactividad propia por página (sin librerías externas) — menú móvil, validación de formularios, filtros y buscadores en vivo, calculadora de bebidas, flipbook, acordeón FAQ, carrusel con autoplay/pausa, y un quiz completo con leaderboard persistido en `localStorage`.
- **Multimedia**: combinación de ilustraciones SVG de autoría propia y fotos/videos aportados por la autora, todos documentados con fuente/autor/licencia en la tabla de créditos más abajo.
- **Contacto**: enlaces `mailto:` en el formulario de `index.html` y en el pie de página de las 8 vistas, más un enlace `tel:`.
- **Diseño e interfaz**: paleta, tipografía y componentes unificados en las 8 páginas, navegación consistente, jerarquía visual clara y contraste verificado (WCAG AA) en los combos de color usados.
## Créditos de multimedia
Por una restricción de red del entorno de desarrollo usado para este proyecto, no fue posible descargar fotografías de bancos de imágenes externos (Unsplash, Pexels, Pixabay) directamente desde el asistente de IA. En su lugar, **la mayoría de las ilustraciones del sitio son piezas vectoriales (SVG) originales**, creadas específicamente para GROUNDS con la paleta de marca del proyecto. Al ser autoría propia, no requieren licencia de terceros.
| Archivo | Fuente | Autor | Licencia |
|---|---|---|---|
| `assets/img/hero-taza.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/historia-ambiente.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/cursos-banner.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/latte-corazon.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/latte-rosetta.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/latte-tulipan.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/pour-frame-1.svg` a `pour-frame-5.svg` | Ilustración propia (secuencia flipbook, alternativa a video) | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/recetario-cata.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/comunidad-tablero.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/trivia-trofeo.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
| `assets/img/noticias-tablon.svg` | Ilustración propia | Cristina Colimba Ramos | Uso libre (autoría propia) |
**Fotos y videos aportados por la autora** (varias ilustraciones SVG de la tabla anterior fueron reemplazadas por estos archivos reales; los SVG se conservan en `assets/img/` como respaldo). Los videos se comprimieron para web a partir de los clips originales (se recortó solo resolución/bitrate, no el contenido):
| Archivo | Usado en | Fuente | Autor | Licencia |
|---|---|---|---|---|
| `assets/video/exterior-cafeteria.mp4` | Carrusel de `historia.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/video/clientes-cafeteria.mp4` | Carrusel de `historia.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/video/baristas-oliendo-catando-cafe.mp4` | Sección de cata en `recetario.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/video/preparandocafe-pourover.mp4` | `cursos.html`, curso de métodos de extracción | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/img/shotdecafebajando.jpg` | Hero de `index.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/img/baristahaciendoartelatte.png` | Banner de `latte-art.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/img/tulipanartelatte.png` | `latte-art.html`, junto al flipbook | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/img/utilesdeestudioenmesa.png` | Banner de `cursos.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/img/mastrena-maquinadecafe.png` | Banner de `recetario.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/img/granosdecafe-cafemolido-latte.png` | Banner de `comunidad.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
| `assets/img/imagen-noticias-equipo-animada.png` | Banner de `noticias.html` | *(completar: banco/autor original)* | — | *(completar: licencia libre de derechos, cita APA)* |
> Nota para la entrega: la rúbrica pide que todo elemento multimedia esté "libre de derechos de autor o bien justificado con normas APA". Completa la columna "Fuente" con el banco de imágenes/video real (ej. Pexels, Pixabay, Freepik) y agrega aquí la cita en formato APA antes de comprimir la carpeta final.
**Sin usar en el sitio:** `videohorizontal_artelatte.mp4` se descartó porque muestra visiblemente el logo real de una cafetería de terceros ("Café Kitsuné") en el vaso y el delantal del barista, lo cual no cumple con el requisito de contenido libre de derechos/apropiado.
**Tipografías (Google Fonts):**
| Fuente | Uso | Licencia |
|---|---|---|
| Poppins | Títulos (display) | SIL Open Font License |
| Inter | Cuerpo de texto | SIL Open Font License |
| Space Mono | Datos, códigos, timestamps | SIL Open Font License |
El bloque de créditos también está visible en el sitio, al final de `historia.html` (sección `#creditos`), enlazado desde el pie de página de las 8 páginas.
## Notas de marca
GROUNDS es una marca ficticia creada para este proyecto académico; no usa el logo, el nombre ni ningún asset visual de una marca comercial real. Cualquier mención a "la experiencia de un partner barista" es puramente narrativa, con fines de ambientación.
**Paleta de color:** la paleta (`css/style.css`, sección `:root`) se inspira en tonos verdes, dorados y neutros cálidos típicos de la industria cafetera, para reforzar visualmente la identidad de una cafetería sin reproducir el logo ni la marca de ninguna empresa real.