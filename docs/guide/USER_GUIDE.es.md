# Guía del usuario de HyperEdit

<p align="center"><a href="USER_GUIDE.md">English</a> · <a href="USER_GUIDE.ko.md">한국어</a> · <a href="USER_GUIDE.zh-Hans.md">简体中文</a> · <a href="USER_GUIDE.ja.md">日本語</a> · <a href="USER_GUIDE.vi.md">Tiếng Việt</a> · <a href="USER_GUIDE.hi.md">हिन्दी</a> · <a href="USER_GUIDE.de.md">Deutsch</a> · <a href="USER_GUIDE.fr.md">Français</a> · Español · <a href="USER_GUIDE.pt.md">Português</a> · <a href="USER_GUIDE.ar.md">العربية</a></p>

HyperEdit es un editor de texto sin formato rápido para macOS, construido en torno a un único archivo grande de notas: de esos a los que sigues añadiendo cosas durante años. Esta guía explica todo lo que puedes hacer con él, en el orden en que probablemente lo encuentres. Los atajos se escriben con los símbolos del Mac: ⌘ Comando, ⇧ Mayúsculas, ⌥ Opción, ⌃ Control.

## Contenido

1. [Instalación y actualización](#1-instalación-y-actualización)
2. [Primer inicio](#2-primer-inicio)
3. [Idioma de la interfaz](#3-idioma-de-la-interfaz)
4. [La ventana](#4-la-ventana)
5. [Nociones básicas de edición](#5-nociones-básicas-de-edición)
6. [Buscar y reemplazar](#6-buscar-y-reemplazar)
7. [Marcadores](#7-marcadores)
8. [Modo columna y multicursor](#8-modo-columna-y-multicursor)
9. [Herramientas de líneas y texto](#9-herramientas-de-líneas-y-texto)
10. [Fragmentos](#10-fragmentos)
11. [Macros](#11-macros)
12. [Plegado de código y marcas de desplazamiento](#12-plegado-de-código-y-marcas-de-desplazamiento)
13. [Editor dividido](#13-editor-dividido)
14. [Apunte rápido](#14-apunte-rápido)
15. [Vista previa de Markdown y colores de sintaxis](#15-vista-previa-de-markdown-y-colores-de-sintaxis)
16. [Temas, tipos de letra y texto CJK](#16-temas-tipos-de-letra-y-texto-cjk)
17. [Guardado, instantáneas y codificaciones](#17-guardado-instantáneas-y-codificaciones)
18. [Referencia de ajustes](#18-referencia-de-ajustes)
19. [Atajos de teclado](#19-atajos-de-teclado)
20. [Archivos que escribe HyperEdit](#20-archivos-que-escribe-hyperedit)
21. [Solución de problemas](#21-solución-de-problemas)
22. [Limitaciones conocidas](#22-limitaciones-conocidas)
23. [Bloques secretos y bloqueo de la app](#23-bloques-secretos-y-bloqueo-de-la-app)
24. [Obtener ayuda](#24-obtener-ayuda)

## 1. Instalación y actualización

**Requisitos:** macOS 15 (Sequoia) o posterior. La app es un binario universal (Apple Silicon e Intel), firmado y notarizado, así que Gatekeeper la abre sin avisos.

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Actualiza más tarde con `brew upgrade --cask hyperedit`. Homebrew 7 puede pedirte que confíes primero en el tap: `brew trust Hyeongcheol-An/tap`.

**DMG:** descarga `HyperEdit-x.y.z-universal.dmg` desde [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), ábrelo y arrastra `HyperEdit.app` a `Applications`. Para verificar una descarga, coloca `SHA256SUMS` junto al DMG y ejecuta `shasum -a 256 -c SHA256SUMS`.

HyperEdit no tiene código de red ni telemetría: nunca se conecta a ningún servidor, y las actualizaciones las haces tú, no la app.

## 2. Primer inicio

HyperEdit abre `~/Documents/HyperEdit/notes.md`. Si ese archivo no existe, se crea con un breve texto de bienvenida en tu idioma: bórralo y empieza a escribir. La idea es que conserves un solo archivo y le vayas añadiendo, pero nada te obliga a ello:

- **⌘N** crea un archivo de texto vacío nuevo (tú eliges el nombre y la carpeta).
- **⌘O** abre cualquier otro archivo de texto. El último archivo abierto se recuerda para el próximo inicio.
- **Archivo › Abrir documento predeterminado** te devuelve a `notes.md`.
- Los archivos binarios (imágenes, PDF, archivos comprimidos…) nunca se cargan en el editor; se abren en su app predeterminada.

La posición del cursor y del desplazamiento se recuerdan por archivo, así que al reabrir un archivo de 30.000 líneas vuelves al punto donde lo dejaste. **⌃⌘E** salta al final del documento, el lugar que normalmente quieres en un archivo de notas.

## 3. Idioma de la interfaz

La interfaz está disponible en once idiomas: English (inglés), 한국어 (coreano), 简体中文 (chino simplificado), 日本語 (japonés), Tiếng Việt (vietnamita), हिन्दी (hindi), Deutsch (alemán), Français (francés), Español, Português (portugués, ortografía brasileña) y العربية (árabe). El texto árabe se escribe de derecha a izquierda, pero la disposición de la ventana — cinta, barra lateral, paneles y editor — se mantiene de izquierda a derecha, como en la mayoría de los editores de código; el texto que escribes sigue su propia dirección.

De forma predeterminada, HyperEdit sigue el idioma del sistema. Para elegir otro:

1. Abre **Ajustes (⌘,)** y mira la sección **Idioma** de la parte superior.
2. Elige un idioma en el menú **Idioma de la interfaz**. Cada idioma aparece en su propia escritura, así que puedes encontrar el tuyo aunque el idioma actual te resulte desconocido. **Predeterminado del sistema** muestra qué idioma te daría el ajuste del sistema.
3. Haz clic en **Reiniciar ahora**. El documento se guarda primero; luego HyperEdit se cierra y vuelve a abrirse en el nuevo idioma. (También puedes seguir trabajando y reiniciar más tarde; la elección ya está guardada.)

La elección se guarda en el mismo lugar que **Ajustes del Sistema › General › Idioma y región › Aplicaciones**, así que ambos coinciden. **Ayuda › Guía del usuario** y el botón **Abrir la guía del usuario** de Ajustes abren esta guía en el idioma actual de la interfaz.

Un idioma que no esté en la lista recurre al inglés (por ejemplo, el chino tradicional). El texto del documento, los nombres de archivo y las fechas que insertas no se ven afectados por el idioma de la interfaz: el día de la semana de la marca de tiempo sigue la configuración regional del sistema.

## 4. La ventana

La disposición sigue la de un editor clásico con cinta de opciones, con la barra de título oculta.

- **Pestañas de la cinta** — **Inicio** (Portapapeles, Buscar, Insertar, Modo, Archivo), **Edición** (Líneas, Mayúsculas y minúsculas, Ordenar, Espacios en blanco, Columna y multicursor, Herramientas, Macro), **Disposición** (Tema, Paneles, Plegado, Markdown, Tamaño de letra), **Avanzado** (Ajustes, carpeta de instantáneas, recarga, documento predeterminado), **Ventana** (pantalla completa, paneles). Cuando la ventana es estrecha, los grupos se repliegan en iconos desde la derecha; la descripción emergente del icono muestra la etiqueta.
- **Barra de pestañas del documento** — el nombre del archivo actual con los botones Nuevo (⌘N) y Abrir (⌘O), además de acceso rápido a Guardar / Deshacer / Rehacer.
- **Barra lateral (⌘1)** — **Archivos** (la carpeta del archivo actual; un clic abre un archivo), **Esquema (⌘3)** (encabezados, líneas `[Título]` y elementos numerados, con un cuadro de filtro; el elemento actual se resalta), **Cronología (⌘4)** (encabezados con marca de tiempo agrupados por mes, los más recientes primero).
- **Panel inferior (⌘2)** — **Resultados de búsqueda**, **Marcadores** y **Salida**, un registro de lo que hizo la app (guardados, reemplazos, errores).
- **Barra de estado** — línea y columna (más la longitud de la selección; pasa el puntero para ver el desplazamiento en caracteres), fin de línea (UNIX / DOS / MAC), codificación del archivo, **COL** mientras el modo columna está activo, número de cursores, número de líneas · tamaño del archivo, el último mensaje de estado, el lenguaje de sintaxis (atenuado mientras los colores de sintaxis están desactivados), un menú de temas (marcado con “· Sistema” mientras se sigue la apariencia del sistema) y el porcentaje de zoom. La mayoría de los elementos se pueden pulsar.

## 5. Nociones básicas de edición

- Escribir sigue siendo rápido en archivos de varios megabytes; solo se compone la parte visible del documento.
- **Ajuste de línea** ⌥Z · **Números de línea** ⌥⌘L · **Zoom** ⌘= / ⌘- / ⌘0 (también en la pestaña Disposición).
- **Ir a la línea** ⌘L · **Final del documento** ⌃⌘E.
- **Insertar fecha y hora** F7 inserta un encabezado con marca de tiempo como `## 2026-10-31 (vie) 14:05`. El día de la semana sigue la configuración regional de tu sistema. Las líneas así alimentan la Cronología.
- La línea actual se resalta y el margen muestra su número en el color del texto.
- Deshacer y rehacer son ilimitados dentro de una sesión, y cada herramienta descrita a continuación es un solo paso de deshacer.

## 6. Buscar y reemplazar

- **Buscar (⌘F)** abre la barra de búsqueda. Escribe una consulta y pulsa Intro: cada coincidencia se lista en el panel inferior con su número de línea, y las coincidencias se resaltan en el editor mientras la lista está abierta. Opciones: expresión regular `.*`, distinguir mayúsculas `Aa`, palabra completa `W`. **F3 / ⇧F3** van a la coincidencia siguiente / anterior. La lista se actualiza sola alrededor de un segundo después de que edites.
- **Reemplazar (⌘R)** añade un campo de reemplazo: reemplaza la coincidencia actual y pasa a la siguiente, o **Reemplazar todo**. Con la expresión regular activada, plantillas como `$1` insertan los grupos capturados. Reemplazar todo es un solo paso de deshacer, incluso con miles de coincidencias.
- **Buscar en archivos (⇧⌘F)** busca en una carpeta (subcarpetas incluidas). Elige la carpeta, limita opcionalmente con máscaras como `*.md;*.txt` y haz clic en una coincidencia para abrir ese archivo en esa línea. Se omiten los archivos ocultos, los paquetes, los archivos binarios y los archivos de más de 20 MB.
- **Seleccionar todas las coincidencias (⌥⌘A)** convierte cada coincidencia en un cursor; consulta el multicursor más abajo.

## 7. Marcadores

**⌘F2** añade un marcador a la línea actual (o lo quita), **F2 / ⌥F2** saltan al marcador siguiente / anterior, y la pestaña **Marcadores** del panel inferior los lista todos; allí puedes dar nombre a un marcador. Los marcadores siguen a sus líneas mientras editas: insertar o eliminar líneas por encima los desplaza, eliminar una línea marcada lo elimina, y deshacer los recupera. Se guardan por documento en `~/Library/Application Support/HyperEdit/bookmarks/`, así que no se escribe nada junto a tus archivos.

## 8. Modo columna y multicursor

- **Modo columna (⌥C)** — mantén pulsada ⌥ y arrastra, o usa ⇧ con las flechas, para seleccionar un rectángulo. Escribir y borrar se aplican entonces a todas las líneas del bloque, las líneas cortas se rellenan con espacio virtual, y copiar / pegar funcionan línea por línea. La barra de estado muestra **COL**. ⌥C de nuevo lo desactiva.
- **Insertar números (⌥⌘N)** — rellena una selección de columna (o cada cursor) con una secuencia: elige el inicio y el incremento; los números se rellenan con ceros hasta el mismo ancho.
- **Multicursor** — ⌘-clic añade un cursor, **⌘D** añade la siguiente aparición del texto seleccionado (o de la palabra en el cursor), **⌥⌘A** selecciona todas las coincidencias de la búsqueda. Lo que escribes va a todos los cursores; Esc vuelve a uno solo. Cada edición multicursor es un solo paso de deshacer.

## 9. Herramientas de líneas y texto

Están en la pestaña **Edición** de la cinta y en el menú **Línea**. Actúan sobre las líneas seleccionadas, o sobre la línea actual cuando no hay nada seleccionado.

| Grupo | Herramientas |
|---|---|
| Líneas | Eliminar línea ⇧⌘K · Duplicar línea ⇧⌘D · Mover línea arriba / abajo ⌥↑ / ⌥↓ · Unir líneas ⇧⌘J · Invertir orden de líneas · Numerar líneas |
| Mayúsculas y minúsculas | Mayúsculas · Minúsculas · Mayúscula inicial · Invertir |
| Ordenar | Creciente · Decreciente · Orden numérico (por el número al inicio de cada línea) · Eliminar líneas duplicadas |
| Espacios en blanco | Eliminar espacios finales · Eliminar espacios iniciales y finales · Eliminar líneas vacías · Tabs → Espacios · Espacios → Tabs |

- **Calcular (⌃⌘=)** evalúa la selección, o la línea actual (la parte después del último `=` si lo hay), y añade ` ⇒ resultado`: `3+0.5+0.25` se convierte en `3+0.5+0.25 ⇒ 3.75`. Ejecutarlo de nuevo en una línea editada reemplaza el resultado anterior. Se admiten: `+ - * / % ^`, paréntesis, números como `1,234` y `1_000`, `sqrt abs round floor ceil min max`, `pi` y `e`. Una expresión que no se puede evaluar se informa en el panel Salida y el texto se deja intacto.
- **Alinear columnas (⌃⌘T)** rellena las columnas separadas por tabulación (las líneas seleccionadas, o el bloque de líneas con tabulaciones alrededor del cursor) para que cada columna empiece en la misma columna de pantalla; los caracteres coreanos, chinos y japoneses cuentan como dos celdas. Si todas las líneas contienen `|`, el bloque se trata como una tabla Markdown: las celdas se rellenan dentro de ` | `, las filas `---` se redibujan y las columnas `--:` se alinean a la derecha.
- **Comentar (⌘/)** comenta o descomenta las líneas con el marcador del tipo de archivo: `//`, `#`, `--`… para código, `<!-- -->` para Markdown y HTML, `/* */` para CSS, `//` para notas sin formato. Si todas las líneas no vacías ya están comentadas, se descomentan todas; si no, se comentan todas, con los marcadores alineados en la sangría menos profunda. Las líneas vacías se omiten.
- **Formatear JSON (⌃⌘J) / Compactar JSON** formatea de forma legible (sangría de 2 espacios) o compacta la selección, o todo el documento cuando no hay nada seleccionado. Se conservan el orden de las claves y el texto de los números, el texto no ASCII no se escapa, y la entrada puede contener comentarios y comas finales (JSONC). Ante un error de sintaxis, el texto se deja intacto, el panel Salida muestra `línea:columna` y el cursor salta allí.

## 10. Fragmentos

Escribe una palabra activadora y pulsa **Tab** para expandirla. Activadores integrados: `todo`, `date`, `time`, `now`, `meeting`, `table`, `link`, `code`. **Insertar fragmento… (⇧⌘I)** los lista todos con un cuadro de filtro, y el botón Fragmento… de la pestaña Inicio hace lo mismo.

El cuerpo de un fragmento puede contener variables — `${date}`, `${time}`, `${datetime}`, `${selection}`, `${clipboard}`, `${filename}` — y puntos de tabulación `$1` … `$9`, `${1:placeholder}` y `$0`. Tras la expansión, Tab / ⇧Tab se mueven entre los puntos de tabulación (un número usado dos veces se convierte en multicursor), y Esc o un clic terminan la sesión.

**Editar fragmentos…** (menú Edición o pestaña Inicio) abre `~/Library/Application Support/HyperEdit/snippets.json` en el propio HyperEdit. Cada entrada tiene un `trigger`, un `name` y un `body`; el archivo se vuelve a leer después de guardarlo, así que un activador nuevo funciona de inmediato.

## 11. Macros

Una macro graba lo que escribes y lo reproduce en otro lugar.

1. **Grabar macro (⇧⌘M)** inicia la grabación; la barra de estado muestra `● REC`. Se graban la escritura (para el coreano y otros IME, los caracteres confirmados), el movimiento del cursor, los borrados, los saltos de línea, pegar, las herramientas de texto y Buscar siguiente (F3, con su consulta). No se graban los clics del ratón, los cambios de selección ni las ediciones multicursor.
2. **⇧⌘M** de nuevo detiene la grabación.
3. **Reproducir macro (⌥⌘M)** la reproduce en el cursor. **Reproducir macro varias veces…** la repite hasta 10.000 veces y se detiene sola cuando un paso de búsqueda no encuentra nada o una pasada no cambia nada: una herramienta cómoda para “hacer esto en cada línea”. Toda la ejecución es un solo paso de deshacer.

La última grabación permanece solo en memoria hasta que sales, así que nada sensible que hayas escrito mientras grababas llega al disco. **Guardar última macro como…** la añade al menú **Macro** de forma permanente; las macros guardadas viven en `~/Library/Application Support/HyperEdit/macros/macros.json`, que **Editar archivo de macros…** abre en el editor.

## 12. Plegado de código y marcas de desplazamiento

**Plegar (⌥⌘←) / Desplegar (⌥⌘→)** ocultan o muestran la región del cursor; **⌥⇧⌘← / ⌥⇧⌘→** pliegan o despliegan todo. Una región es:

- las líneas sangradas bajo la línea actual (las líneas vacías se ignoran),
- en Markdown, todo lo que hay bajo un encabezado `#` hasta el siguiente encabezado del mismo nivel o superior (los bloques de código delimitados también se pliegan),
- en código, una línea que termina en `{`, `[` o `(` hasta la línea de su cierre.

Haz clic en el chevrón del margen o en la píldora `⋯ N líneas` tras una línea plegada para alternarla con el ratón. Mover el cursor a una línea plegada (buscar, ir a la línea, marcador, deshacer) la despliega; ↑ / ↓ saltan por encima de los pliegues. Los pliegues siguen tus ediciones y duran la sesión.

**Marcas de desplazamiento** — una franja fina en el borde derecho del editor muestra las coincidencias de búsqueda (color de acento), los marcadores (color de aviso), la línea del cursor y los encabezados plegados en sus posiciones relativas dentro del archivo. Se oculta cuando todo el documento cabe en pantalla. Desactívala en **Visualización › Marcas de desplazamiento** o en el grupo Plegado de la pestaña Disposición.

## 13. Editor dividido

**⌘\\** muestra el mismo documento en dos editores, lado a lado; **Visualización › Dividir › Dividir apilado** los pone uno encima del otro, y la pestaña Disposición tiene los mismos botones. Ambas vistas editan el mismo texto y comparten un único historial de deshacer (escribe en una, ⌘Z en la otra), pero se desplazan de forma independiente, así que puedes leer una parte del archivo mientras escribes en otra. Los comandos, la barra de estado y la vista previa de Markdown siguen al editor en el que hiciste clic por última vez; **⌥⌘\\** pasa el foco al otro. La barra de estado muestra **SPLIT** mientras la división está activa; ⌘\\ de nuevo la cierra.

## 14. Apunte rápido

**Apunte rápido (⇧⌘N)** abre un pequeño panel flotante para añadir una nota sin dejar lo que estabas haciendo. Escribe la nota, pulsa **⌘↩**, y se añade al final del documento — con un encabezado con marca de tiempo de forma predeterminada —, se guarda de inmediato y se puede deshacer en un solo paso. El panel se oculta después y el foco vuelve a la app en la que estabas. **Esc** cierra el panel y conserva el borrador para la próxima vez.

Como el panel no activa HyperEdit, también funciona desde cualquier otra app mediante un **atajo global**: **⌃⌥N** de forma predeterminada. En Ajustes puedes desactivarlo o elegir ⌃⌥Space, ⌃⇧Space o ⌃⌥⌘N en su lugar, y desactivar el encabezado con marca de tiempo. El atajo usa el servicio de teclas rápidas del sistema, así que no se necesita el permiso de Accesibilidad. Si otra app ya posee la combinación, el panel Salida lo indica al iniciar: elige otra.

## 15. Vista previa de Markdown y colores de sintaxis

- **Vista previa de Markdown (⇧⌘P)** divide la ventana con una vista renderizada del archivo actual a la derecha: encabezados, listas y listas de tareas, tablas, código delimitado, citas, enlaces e imágenes, con el estilo del tema actual. Sigue la posición de desplazamiento del editor y se vuelve a renderizar poco después de que dejes de escribir. Los enlaces se abren en tu navegador; el HTML sin procesar del archivo se muestra como texto, nunca se ejecuta. Los archivos de más de 2 MB muestran un aviso en lugar de la vista previa. La barra de estado muestra **MD** mientras está activa.
- **Colores de sintaxis (⌃⌘H)** se eligen según la extensión del archivo y se muestran en la barra de estado. Las notas y Markdown reciben un conjunto de reglas ligero — URL, fechas y horas, encabezados, líneas `[Título]`, marcadores de lista y casillas de tarea `[ ]` / `[x]`, `#etiquetas`, etiquetas `clave:`, `**negrita**`, `` `código` `` y flechas `⇒ → ->` — y unos 20 lenguajes de programación reciben comentarios, cadenas, números, palabras clave, nombres de funciones y de tipos. Los colores se dibujan solo en las líneas visibles, así que nunca cambian el archivo ni ralentizan la escritura. Las construcciones que abarcan varias líneas conservan su color hasta que se cierran: comentarios de bloque (`/* */`, `<!-- -->`), cadenas multilínea (`"""` de Swift y Python, plantillas literales de JavaScript, cadenas sin procesar de Go, `r#"…"#` de Rust) y bloques de código delimitados de Markdown, que se colorean con el lenguaje indicado en la cadena de información (```` ```python ````). Escribir un delimitador de apertura o de cierre vuelve a colorear al instante las líneas de abajo.
- **Gramáticas definidas por el usuario.** Para colorear un lenguaje que HyperEdit no conoce, o para cambiar uno integrado, coloca un archivo `*.json` en `~/Library/Application Support/HyperEdit/grammars/`. **Archivo › Abrir carpeta de gramáticas…** crea la carpeta con un `example.json` que puedes copiar y un README que explica cada clave — `name`, `extensions` o `filenames`, `lineComments`, `blockComment`, `strings`, `multilineStrings`, `keywords`, `types`, `constants`, `builtins`, `caseInsensitive`. **Archivo › Recargar gramáticas** aplica tus cambios sin reiniciar; la barra de estado muestra el nombre de la gramática, Comentar (⌘/) usa sus marcadores de comentario y un archivo que no se puede analizar se omite con un mensaje en el panel Salida.

## 16. Temas, tipos de letra y texto CJK

**Temas.** La app incluye 22 paletas: 5 claras y 17 oscuras. De forma predeterminada sigue la apariencia del sistema: **Hyper Light** en modo claro, **Hyper Dark** en modo oscuro. Elige un tema en la pestaña Disposición, en el menú de temas de la barra de estado, en **Visualización › Tema** o con ⌥⌘] / ⌥⌘[ para fijarlo; **Seguir la apariencia del sistema** está en los mismos menús y en Ajustes. Las mismas paletas están disponibles para el editor Zed (`hyperedit-themes.json` en cada versión publicada).

**Cursor y opacidad de la ventana.** Ajustes › **Apariencia** elige la forma del cursor — **Barra** (la predeterminada), **Bloque** (la celda del carácter se tiñe con el color del cursor para que el carácter siga siendo legible) o **Subrayado** — y si parpadea; los cursores adicionales del multicursor y del modo columna usan la misma forma. **Opacidad de la ventana** (50–100 %) hace translúcida toda la ventana — editor, cinta, paneles y barra de estado por igual — mientras el texto, los iconos y los bordes siguen sólidos, y **Desenfocar detrás de la ventana** añade el desenfoque del sistema. Visualización › Opacidad de la ventana ofrece pasos de 100 / 90 / 80 / 70 %.

**Tipos de letra.** HyperEdit usa **Fira Code** cuando está instalado y, si no, el tipo de letra monoespaciado del sistema. El texto coreano se dibuja con un tipo de letra aparte — **D2Coding** de forma predeterminada, cuando está instalado — escalado para que una sílaba hangul mida exactamente dos celdas latinas de ancho, lo que mantiene rectas las tablas alineadas con tabulaciones. Las ligaduras, la altura de línea, ambas familias tipográficas y la escala del hangul están en Ajustes. El texto chino y japonés usa los tipos de letra alternativos del sistema y también cuenta como dos celdas en Alinear columnas.

## 17. Guardado, instantáneas y codificaciones

- **Guardado automático** se ejecuta dos segundos después de que dejes de escribir (⌘S guarda ahora). Al salir, al cerrar la ventana y al cambiar de archivo, el documento se guarda de inmediato, así que no se pierde nada en la ventana de dos segundos. Cada escritura es atómica.
- **Instantáneas.** Antes del primer guardado de cada sesión se almacena una copia del archivo en `~/Library/Application Support/HyperEdit/snapshots` (**Archivo › Abrir carpeta de instantáneas**). Se conservan las 20 más recientes por archivo y se elimina todo lo que tenga más de 90 días.
- **Cambios externos.** Si otro programa cambia el archivo mientras está abierto y no tienes ediciones sin guardar, HyperEdit lo recarga y mantiene el cursor donde estaba. Si sí tienes ediciones sin guardar, la versión externa se guarda como instantánea y se muestra un aviso; guardar entonces la sobrescribe.
- **Seguridad.** Nunca se escribe un búfer vacío sobre un archivo que tenía contenido. Si el guardado falla al salir, se escribe una copia de emergencia en la carpeta de instantáneas y se te pregunta si quieres salir de todos modos.
- **Codificaciones.** Los archivos se leen primero como UTF-8, luego EUC-KR (CP949), CP1252 y Latin-1, y se guardan en la misma codificación (se conserva el BOM de UTF-8). Si escribes un carácter que la codificación original no puede almacenar, el archivo se guarda como UTF-8 y la barra de estado lo indica. Un archivo que no se puede decodificar en ninguna de estas codificaciones no se abre en absoluto, en lugar de dañarse.
- **Finales de línea** (UNIX / DOS / MAC) se detectan y se conservan; Apunte rápido y las herramientas de texto usan el propio del archivo.
- **Exportar.** **Archivo › Exportar como HTML…** guarda el documento como un único archivo HTML autónomo — Markdown renderizado como en la vista previa, notas y código como un bloque con colores de sintaxis — y **Archivo › Exportar como PDF…** imprime la misma página en un PDF paginado (Carta en EE. UU., Canadá y México, A4 en el resto; márgenes de 36 pt; sin encabezado ni pie de página). El panel de guardado te permite elegir el tema (actual, Hyper Light, Hyper Dark) y, para notas y código, los números de línea. La página exportada no contiene scripts ni carga nada de la red; las rutas relativas de las imágenes se conservan, así que guarda el HTML junto al archivo Markdown. La exportación a PDF funciona con archivos de hasta 2 MB. Los bloques secretos (sección 23) se exportan como `••••••••`.

## 18. Referencia de ajustes

Abre Ajustes con **⌘,** o con la pestaña Avanzado.

| Sección | Qué controla |
|---|---|
| Idioma | Idioma de la interfaz (Predeterminado del sistema o uno de once idiomas), **Reiniciar ahora**, **Abrir la guía del usuario** |
| Tipo de letra | Familia del tipo de letra latino, tamaño, ligaduras, altura de línea |
| Hangul | Familia del tipo de letra hangul, la corrección de ancho 2:1, escala del hangul; muestra si el tipo de letra está instalado |
| Tema | Seguir la apariencia del sistema, selector de tema |
| Archivos | El archivo actual, el documento predeterminado y la carpeta de instantáneas, con botones para abrirlos |
| Apunte rápido | Atajo global (Desactivado / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N), encabezado con marca de tiempo sí/no |
| Apariencia | Estilo del cursor (Barra / Bloque / Subrayado), parpadeo, opacidad de la ventana 50–100 %, desenfoque detrás de la ventana |
| Secretos | Ocultar bloques secretos, volver a ocultar tras (10 / 30 / 60 s / Nunca), vaciar el portapapeles tras copiar un secreto (Desactivado / 10 / 30 / 60 s) |

La visibilidad de los paneles, el ajuste de línea, los números de línea, los colores de sintaxis, las marcas de desplazamiento, la división y la pestaña de la cinta se recuerdan automáticamente.

## 19. Atajos de teclado

| Atajo | Acción | Atajo | Acción |
|---|---|---|---|
| ⌘N | Nuevo documento | ⌘O | Abrir |
| ⌘S | Guardar | ⌘F | Buscar |
| ⌘R | Reemplazar | ⇧⌘F | Buscar en archivos |
| F3 / ⇧F3 | Coincidencia siguiente / anterior | ⌘L | Ir a la línea |
| ⌃⌘E | Final del documento | ⌥C | Modo columna |
| ⌘D | Añadir siguiente aparición | ⌥⌘A | Seleccionar todas las coincidencias |
| ⌥⌘N | Insertar números | F7 | Insertar marca de tiempo |
| ⌘F2 | Alternar marcador | F2 / ⌥F2 | Marcador siguiente / anterior |
| ⇧⌘K | Eliminar línea | ⇧⌘D | Duplicar línea |
| ⌥↑ / ⌥↓ | Mover línea arriba / abajo | ⇧⌘J | Unir líneas |
| ⌃⌘= | Calcular | ⌃⌘T | Alinear columnas |
| ⌘/ | Comentar | ⌃⌘J | Formatear JSON |
| ⇧⌘I | Insertar fragmento | Tab | Expandir fragmento / siguiente punto de tabulación |
| ⇧⌘M | Grabar / detener macro | ⌥⌘M | Reproducir macro |
| ⌥⌘← / ⌥⌘→ | Plegar / desplegar | ⌥⇧⌘← / ⌥⇧⌘→ | Plegar todo / desplegar todo |
| ⌘\\ | Dividir editor | ⌥⌘\\ | Pasar al otro editor |
| ⇧⌘N | Apunte rápido | ⌃⌥N | Apunte rápido desde cualquier app (configurable) |
| ⌘1 | Barra lateral | ⌘2 | Panel inferior |
| ⌘3 | Esquema | ⌘4 | Cronología |
| ⌥⌘L | Números de línea | ⌥Z | Ajuste de línea |
| ⇧⌘P | Vista previa de Markdown | ⌃⌘H | Colores de sintaxis |
| ⌥⌘] / ⌥⌘[ | Tema siguiente / anterior | ⌘= / ⌘- / ⌘0 | Acercar / alejar / restablecer |
| ⌥⌘S | Mostrar / ocultar bloques secretos | ⌘, | Ajustes |
| ⌃⌘L | Bloquear HyperEdit (Touch ID) | | |
| ⌘Q | Salir (guarda primero) | | |

## 20. Archivos que escribe HyperEdit

HyperEdit solo toca los archivos que abres y sus propios datos:

| Ruta | Contenido |
|---|---|
| `~/Documents/HyperEdit/notes.md` | El documento predeterminado (se crea en el primer inicio si no existe) |
| `~/Library/Application Support/HyperEdit/snapshots/` | Instantáneas previas al guardado y copias de emergencia |
| `~/Library/Application Support/HyperEdit/bookmarks/` | Un archivo JSON por documento con marcadores |
| `~/Library/Application Support/HyperEdit/snippets.json` | Tus fragmentos |
| `~/Library/Application Support/HyperEdit/grammars/` | Gramáticas definidas por el usuario (`*.json`), con `example.json` y un README |
| `~/Library/Application Support/HyperEdit/macros/macros.json` | Macros guardadas |
| `~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist` | Preferencias, incluido el idioma de la interfaz |

No se escribe nada junto a tus documentos, y nada sale de tu Mac.

## 21. Solución de problemas

- **El idioma no cambió.** El nuevo idioma se aplica tras un reinicio: usa **Reiniciar ahora** en Ajustes o sal y vuelve a abrir la app. Si el idioma del sistema es uno que HyperEdit no tiene, muestra inglés; elige un idioma explícitamente en Ajustes.
- **Un archivo no se abre.** Los archivos binarios se abren en su app predeterminada a propósito. Un archivo de texto en una codificación distinta de UTF-8, EUC-KR, CP1252 o Latin-1 se rechaza en lugar de dañarse; conviértelo antes con otra herramienta.
- **El atajo global de Apunte rápido no hace nada.** Puede que otra app posea la combinación, o que ⌃Space / ⌃⌥Space estén ocupados por el cambio de fuente de entrada en Ajustes del Sistema › Teclado. Elige ⌃⌥N o ⌃⌥⌘N en Ajustes. El panel Salida informa del resultado del registro al iniciar.
- **El texto coreano se ve demasiado ancho o demasiado estrecho en las tablas.** Instala D2Coding o ajusta la escala del hangul en Ajustes; la corrección de ancho 2:1 necesita un tipo de letra hangul monoespaciado.
- **Guardé algo por error.** Abre la carpeta de instantáneas (**Archivo › Abrir carpeta de instantáneas**): allí está la copia tomada antes del primer guardado de la sesión, además de las copias hechas cuando se detectaron cambios externos.
- **La cinta solo muestra iconos.** La ventana es demasiado estrecha para esa pestaña; ensánchala o pasa el puntero por un icono para ver su etiqueta.

## 22. Limitaciones conocidas

- Los colores de sintaxis siguen los comentarios de bloque, las cadenas multilínea y los delimitadores de Markdown a través de las líneas, pero solo se admiten delimitadores de cadena que abren y cierran con el mismo símbolo y un único par de comentario de bloque por lenguaje, y las gramáticas de usuario son listas de palabras sin reglas de expresiones regulares. La vista previa de Markdown es una vista, no un editor.
- Las macros graban solo la edición con el teclado (sin pasos de ratón, selección ni multicursor). Calcular y Alinear columnas manejan solo aritmética simple y tablas con tabulaciones / barras verticales.
- Los fragmentos, las macros y las gramáticas de usuario se editan como archivos JSON; no hay un editor gráfico para ellos.
- La exportación escribe solo el documento completo, sin exportar la selección ni varios archivos, sin opciones de página o de tipo de letra y sin índice en el PDF.
- Los bloques secretos se ocultan solo en pantalla: el archivo, los guardados automáticos, las instantáneas y los resultados de Buscar en archivos de otros archivos son texto sin formato, y la barra de ocultación muestra la longitud de cada línea. El bloqueo de la app oculta la ventana; no cifra nada, y una hoja que estaba abierta al bloquear (Ir a la línea, Insertar números, el selector de fragmentos) permanece por encima de la pantalla de bloqueo sin mostrar el documento.
- Los pliegues duran la sesión y no se guardan por archivo; arrastrar con el ratón sobre una línea plegada sigue seleccionando el texto oculto.
- Los documentos que son una sola línea de un megabyte o más tardan en abrirse y en moverse por ellos; Compactar JSON avisa antes de producir uno.
- Solo archivos locales; sin sincronización en la nube y sin app para iOS por ahora.
- Los idiomas distintos de los once indicados recurren al inglés.

## 23. Bloques secretos y bloqueo de la app

**Bloques secretos.** Un bloque de código delimitado cuya cadena de información empieza por `secret` se oculta en el editor:

````markdown
```secret bank
login: me@example.com
password: hunter2
```
````

Cada línea entre los delimitadores se dibuja como una barra en blanco con `••••••••`; las líneas de los delimitadores siguen visibles para que veas dónde está el bloque y para qué sirve. La regla es la misma en archivos Markdown y de texto sin formato. Mueve el cursor dentro del bloque — haz clic en él, usa ↑ / ↓, Ir a la línea, un resultado de búsqueda o un marcador — y todo el bloque se muestra y se puede editar; saca el cursor y se vuelve a ocultar. Solo cambia la visualización: el texto sigue en el archivo, así que Buscar, Reemplazar, deshacer y guardar funcionan exactamente igual que antes.

- **Mostrar secretos (⌥⌘S)** en el menú Edición muestra todos los bloques a la vez; tras **Ajustes › Secretos › Volver a ocultar tras** (10 / 30 / 60 s, 30 s de forma predeterminada, o Nunca) se vuelven a ocultar y el panel Salida lo registra. Mientras tanto la barra de estado muestra `REVEALED`, y `•••• N` mientras N bloques están ocultos. **Edición › Ocultar bloques secretos** desactiva la ocultación por completo.
- Las líneas secretas se muestran como `••••••••` en la lista de Resultados de búsqueda (la coincidencia y el número de línea siguen funcionando), el Esquema y la Cronología las omiten, y se censuran en la vista previa de Markdown y en las exportaciones HTML / PDF.
- **Vaciado automático del portapapeles.** Cuando una copia o un corte incluye una línea secreta — también las copias con multicursor y en modo columna —, el portapapeles se vacía tras **Ajustes › Secretos › Vaciar el portapapeles tras copiar un secreto** (Desactivado / 10 / 30 / 60 s, 30 s de forma predeterminada), salvo que hayas copiado otra cosa entretanto. **Edición › Vaciar portapapeles** lo vacía de inmediato.
- Los bloques secretos se pliegan como cualquier bloque delimitado (⌥⌘←).

> Ocultar no es cifrar. El archivo, los guardados automáticos y las instantáneas son texto sin formato, y cualquiera que tenga el archivo puede leer los secretos. La función los mantiene fuera de tu pantalla, de las capturas de pantalla, de los resultados de búsqueda, de la vista previa y de las exportaciones mientras trabajas.

**Bloqueo de la app (Touch ID).** **HyperEdit › Bloquear HyperEdit (⌃⌘L)** (el menú de la aplicación, debajo de Ajustes…) cubre toda la ventana — cinta, barra lateral, editor, paneles y barra de estado — con una pantalla de bloqueo opaca en el tema actual, cierra una ventana de Ajustes abierta y oculta el panel de Apunte rápido. Mientras está bloqueado no se muestra nada del documento, ni siquiera el nombre del archivo. Haz clic en **Desbloquear** (o pulsa Return) para autenticarte con **Touch ID**; si Touch ID falla o el Mac no lo tiene, macOS recurre a tu contraseña de inicio de sesión. Si cancelas, HyperEdit sigue bloqueado y el botón vuelve a intentarlo.

- **Ajustes › Bloqueo de la app.** *Pedir Touch ID o contraseña para abrir HyperEdit* (desactivado de forma predeterminada) inicia la app bloqueada: el documento se carga y el guardado automático sigue funcionando, pero no se ve nada hasta que te autenticas. *Bloquear tras inactividad* (Nunca / 1 / 5 / 15 / 30 minutos, Nunca de forma predeterminada) bloquea tras ese tiempo sin pulsar una tecla ni hacer clic en HyperEdit, con independencia de la opción de inicio. *Bloquear cuando el Mac entra en reposo o se bloquea la pantalla* (activado de forma predeterminada) se aplica mientras la opción de inicio está activada. Un texto indica si Touch ID está disponible en este Mac.
- Mientras está bloqueado, la entrada de teclado se descarta y la barra de menús no se puede abrir; solo siguen funcionando ⌘Q, ⌘H / ⌥⌘H, ⌘M, ⌘W, ⌃⌘F y el menú del Dock. El atajo global de Apunte rápido muestra la solicitud de desbloqueo en lugar del panel y abre el panel una vez que te has autenticado.
- Es un bloqueo de privacidad para la pantalla, no cifrado: los archivos del disco no cambian y cualquier otra app puede leerlos. La opción *Pedir…* no se puede activar mientras el Mac no tenga ni Touch ID ni contraseña de inicio de sesión, así que no puedes quedarte fuera.

## 24. Obtener ayuda

- Informes de errores e ideas: [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) y [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions).
- Problemas de seguridad: consulta [SECURITY.md](../../SECURITY.md) para informar de forma privada.
- Traducciones: las cadenas de la interfaz están en `l10n/ui.<language>.json` en el repositorio y esta guía en `docs/guide/`; las correcciones son bienvenidas como pull requests — consulta [CONTRIBUTING.md](../../CONTRIBUTING.md).

HyperEdit es software libre bajo la licencia MIT. Su disposición está inspirada en la cinta clásica de UltraEdit; UltraEdit es una marca comercial de IDM Computer Solutions, Inc., y HyperEdit no está afiliado a IDM.
