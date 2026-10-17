/* Geometría pura de la píldora de la scrollbar Aqua. Sin GTK ni cairo: solo
 * aritmética, para que tests/test-aqua-geometry.c la enlace sin display. El
 * widget (aqua-scrollbar.c) la usa tanto para dibujar como para el drag
 * inverso, de modo que la píldora siga al cursor exactamente (sin jitter). */
#include "aqua-geometry.h"

#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

#define AQUA_SLIDER_MIN_LEN 120.0   /* largo mínimo de la píldora (~120px (pedido del dueño): que el gel se aprecie) */

gboolean
aqua_slider_geometry (double value, double lower, double upper,
                          double page, double h,
                          double *out_y, double *out_len)
{
  if (out_y)   *out_y = 0.0;
  if (out_len) *out_len = 0.0;

  double span = upper - lower;
  /* Todo el contenido visible (o datos degenerados): sin píldora. */
  if (span <= page || span <= 0.0 || h <= 0.0)
    return FALSE;

  double frac = page / span;
  double len  = MAX (h * frac, AQUA_SLIDER_MIN_LEN);
  if (len > h) len = h;                 /* nunca más larga que el canal */

  double range = span - page;           /* recorrido del valor */
  double travel = h - len;              /* recorrido en px de la píldora */
  double y = (range > 0.0 && travel > 0.0)
               ? (value - lower) / range * travel
               : 0.0;

  if (out_y)   *out_y = y;
  if (out_len) *out_len = len;
  return TRUE;
}
