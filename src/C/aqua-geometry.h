#pragma once
#include <glib.h>
G_BEGIN_DECLS

/* Geometría pura píldora↔valor de la scrollbar Aqua (It7AquaScrollbar),
 * extraída del widget para poder testearla sin GTK ni display.
 *
 * Dado el estado de un GtkAdjustment (value/lower/upper/page) y la altura útil
 * del canal `h` (px), calcula la posición `*out_y` (px desde arriba) y el largo
 * `*out_len` (px) de la píldora.
 *
 * Devuelve FALSE cuando NO hay píldora que dibujar (todo el contenido cabe:
 * upper-lower <= page); en ese caso out_y y out_len quedan en 0 y el widget
 * pinta solo el canal.
 *
 * Fórmula (la MISMA que usa el drag inverso para no producir jitter):
 *   frac  = page / (upper - lower)
 *   len   = MAX (h * frac, 24.0)            // mínimo Tiger ~24px
 *   range = upper - lower - page
 *   y     = range > 0 ? (value - lower)/range * (h - len) : 0
 */
gboolean aqua_slider_geometry (double value, double lower, double upper,
                                   double page, double h,
                                   double *out_y, double *out_len);

G_END_DECLS
