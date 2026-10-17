#pragma once
#include <cairo.h>
#include <glib.h>
G_BEGIN_DECLS

/* Arte vectorial de la barra de desplazamiento Aqua de Mac OS X Tiger
 * (it7-aqua-art.c). Cairo puro, sin GTK: lo comparten el widget
 * AquaScrollbar y el generador de las imágenes que usa el CSS de las
 * barras nativas, así todas salen de la MISMA base.
 *
 * Unidades: «píxeles Tiger». La barra mide AQUA_ART_W de ancho y la
 * matriz del cairo_t del llamador decide la escala (HiDPI, zoom): a 1x
 * reproduce las capturas de Tiger; a 2x se rasteriza el mismo dibujo, nítido.
 * Se dibuja SIEMPRE en vertical; la horizontal de Tiger es exactamente la
 * traspuesta (aqua_art_transpose). */

#define AQUA_ART_W           15.0  /* ancho de la barra */
#define AQUA_ART_ARROWS      32.0  /* bloque ▲ | ▼ al pie (15 + separador + 16) */
#define AQUA_ART_THUMB_TOP    7.0  /* primera fila que puede ocupar el pomo */
#define AQUA_ART_THUMB_END   33.0  /* filas finales vedadas al pomo (flechas + 1) */

typedef enum {
  AQUA_ART_PRESS_NONE = 0,
  AQUA_ART_PRESS_UP,     /* ▲ (◀ en horizontal) pulsada */
  AQUA_ART_PRESS_DOWN,   /* ▼ (▶ en horizontal) pulsada */
} AquaArtPress;

/* Barra vertical completa de largo `len`: remate superior, canal, pomo en
 * [thumb_y, thumb_y + thumb_len) y flechas juntas al pie. El moteado del cuerpo
 * del pomo queda quieto en el canal (parallax). Con thumb_len <= 0 dibuja la
 * barra sin pomo (para estilos que pintan su propia píldora). */
void aqua_art_draw (cairo_t *cr, double len, double thumb_y,
                        double thumb_len, AquaArtPress press);

/* Solo el pomo (con su sombra), con el moteado anclado al pomo: las piezas
 * del 3-slice del CSS de las barras nativas, que no pueden hacer parallax. */
void aqua_art_draw_thumb (cairo_t *cr, double thumb_y, double thumb_len);

/* Solo el canal con sus dos remates de gel y sin flechas (barras nativas de
 * GTK4, que no tienen steppers). */
void aqua_art_draw_trough (cairo_t *cr, double len);

/* Intercambia x↔y en la matriz: lo que se dibuje después sale en horizontal. */
void aqua_art_transpose (cairo_t *cr);

G_END_DECLS
