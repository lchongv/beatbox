/* aqua-art.c — la barra de desplazamiento Aqua de Mac OS X Tiger como
 * dibujo vectorial (cairo puro, sin GTK).
 *
 * Anatomía medida en capturas reales de Tiger a 1x (ver aqua-art-data.h):
 * una columna de GEL blanco de 15 px con remates redondeados arriba y abajo;
 * dentro, el CANAL hundido con extremos semicirculares (r = 7,5) y su sombra
 * interior («copa»); el POMO es una cápsula de 13 px (semicírculos r = 6,5)
 * con anillo de contorno azul→gris, cuerpo de gel con un moteado de 16 filas
 * y sombra difusa; las FLECHAS ▲▼ van juntas al pie (15 + separador + 16).
 *
 * Como en Tiger el pomo es un 3-slice: remates de 10 filas fijos arriba y
 * abajo (su aspecto no depende del largo) y un cuerpo con la tesela de
 * moteado. En la barra completa esa tesela se queda quieta en el canal
 * (parallax: el pomo la barre al moverse), anclada donde coincide con Tiger
 * con el pomo arriba del todo. La horizontal es la misma barra traspuesta.
 *
 * Todo son trazados, degradados y una malla de degradado polar en los
 * casquetes del pomo: a 1x reproduce Tiger y a cualquier otra escala se
 * rasteriza el mismo dibujo. */
#include "aqua-art.h"
#include "aqua-art-data.h"
#include <math.h>

#define GROOVE_R  7.5   /* semicírculo de los extremos del canal */
#define TOP_PIECE 6.0   /* remate de gel superior: filas 0..5 */

/* Degradado horizontal con un stop en el CENTRO de cada píxel: a 1x da el
 * perfil exacto y a más escala lo interpola sin escalones. */
static cairo_pattern_t *
gray_profile (const double *v, int n, double x0)
{
  cairo_pattern_t *p = cairo_pattern_create_linear (x0, 0, x0 + n, 0);
  for (int i = 0; i < n; i++)
    cairo_pattern_add_color_stop_rgb (p, (i + 0.5) / n, v[i] / 255.0, v[i] / 255.0, v[i] / 255.0);
  return p;
}

static cairo_pattern_t *
rgb_profile (const guint8 (*v)[3], int n, double x0, double x1)
{
  cairo_pattern_t *p = cairo_pattern_create_linear (x0, 0, x1, 0);
  for (int i = 0; i < n; i++)
    cairo_pattern_add_color_stop_rgb (p, (i + 0.5) / n,
                                      v[i][0] / 255.0, v[i][1] / 255.0, v[i][2] / 255.0);
  return p;
}

/* Rellena el rectángulo con `p` y lo libera. */
static void
fill_rect (cairo_t *cr, cairo_pattern_t *p, double x, double y, double w, double h)
{
  cairo_set_source (cr, p);
  cairo_rectangle (cr, x, y, w, h);
  cairo_fill (cr);
  cairo_pattern_destroy (p);
}

static void
paint_clipped (cairo_t *cr, cairo_pattern_t *p, double y, double h)
{
  cairo_save (cr);
  cairo_rectangle (cr, 0, y, AQUA_ART_W, h);
  cairo_clip (cr);
  cairo_set_source (cr, p);
  cairo_paint (cr);
  cairo_restore (cr);
  cairo_pattern_destroy (p);
}

static void
capsule (cairo_t *cr, double x0, double y0, double w, double h)
{
  double r = w / 2.0;
  cairo_new_path (cr);
  cairo_arc (cr, x0 + r, y0 + r, r, G_PI, 2 * G_PI);
  cairo_arc (cr, x0 + r, y0 + h - r, r, 0, G_PI);
  cairo_close_path (cr);
}

/* Trazo suave (bezier con el punto de control doble) medido desde y0; flip
 * = -1 lo refleja para el extremo opuesto. */
static void
soft_stroke (cairo_t *cr, const double pts[3][2], double a, double w,
             double y0, double flip)
{
  cairo_new_path (cr);
  cairo_move_to (cr, pts[0][0], y0 + flip * pts[0][1]);
  cairo_curve_to (cr, pts[1][0], y0 + flip * pts[1][1],
                      pts[1][0], y0 + flip * pts[1][1],
                      pts[2][0], y0 + flip * pts[2][1]);
  cairo_set_line_width (cr, w);
  cairo_set_source_rgba (cr, 0, 0, 0, a);
  cairo_stroke (cr);
}

/* ── columna de gel y canal ───────────────────────────────────────── */

/* Remate exterior de la columna de gel: fila de contorno + 4 filas que se
 * oscurecen hacia el borde + la «abolladura» donde la banda oscura del gel
 * dobla con la curva. y_edge = borde (0 arriba, len abajo). */
static void
outer_end (cairo_t *cr, double y_edge, double flip)
{
  fill_rect (cr, gray_profile (ART_EDGE, 15, 0), 0, flip > 0 ? y_edge : y_edge - 1, 15, 1);
  cairo_pattern_t *g = cairo_pattern_create_linear (0, y_edge, 0, y_edge + flip * 5);
  cairo_pattern_add_color_stop_rgba (g, 0.0, 0, 0, 0, 0);
  for (int i = 0; i < 4; i++)
    cairo_pattern_add_color_stop_rgba (g, (i + 1.5) / 5.0, 0, 0, 0, ART_END_DARK[i]);
  cairo_pattern_set_extend (g, CAIRO_EXTEND_NONE);
  fill_rect (cr, g, 0, MIN (y_edge, y_edge + flip * 5), 15, 5);
  soft_stroke (cr, ART_DENT, ART_DENT_A, ART_DENT_W, y_edge, flip);
}

/* Sombra interior de un extremo del canal: degradado radial elíptico. */
static cairo_pattern_t *
groove_end_shadow (double cy, double flip)
{
  cairo_pattern_t *g = cairo_pattern_create_radial (0, 0, 0, 0, 0, 1);
  for (int i = 0; i < 8; i++)
    cairo_pattern_add_color_stop_rgba (g, i / 7.0, 0, 0, 0, ART_GS_STOPS[i]);
  cairo_matrix_t m;
  cairo_matrix_init_translate (&m, ART_GS_X, cy + flip * ART_GS_DY);
  cairo_matrix_scale (&m, ART_GS_KX, ART_GS_KY);
  cairo_matrix_invert (&m);
  cairo_pattern_set_matrix (g, &m);
  return g;
}

/* Columna de gel + canal. `bottom` es lo que ocupa la pieza de gel inferior:
 * el bloque de flechas o, sin flechas, un remate como el de arriba. */
static void
draw_body (cairo_t *cr, double len, double bottom)
{
  fill_rect (cr, gray_profile (ART_GEL, 15, 0), 0, 0, 15, len);
  outer_end (cr, 0, 1);
  outer_end (cr, len, -1);

  /* El extremo inferior del canal es el espejo exacto del superior: la fila
   * r de arriba equivale a la (mirror - 1 - r) de abajo. */
  double mirror = len - bottom + TOP_PIECE;
  double top_cy = ART_GROOVE_CY, bot_cy = mirror - ART_GROOVE_CY;
  soft_stroke (cr, ART_LIP, ART_LIP_A, ART_LIP_W, 0, 1);
  soft_stroke (cr, ART_LIP, ART_LIP_A, ART_LIP_W, mirror, -1);

  cairo_save (cr);
  cairo_new_path (cr);
  cairo_arc (cr, 7.5, top_cy, GROOVE_R, G_PI, 2 * G_PI);
  cairo_arc (cr, 7.5, bot_cy, GROOVE_R, 0, G_PI);
  cairo_close_path (cr);
  cairo_clip (cr);
  cairo_pattern_t *track = gray_profile (ART_TRACK, 15, 0);
  cairo_set_source (cr, track);
  cairo_paint (cr);
  cairo_pattern_destroy (track);
  /* La «copa» acaba a ART_CUP del centro de cada semicírculo; el resto del
   * canal es el perfil liso. */
  paint_clipped (cr, groove_end_shadow (top_cy, 1), 0, top_cy + ART_CUP);
  paint_clipped (cr, groove_end_shadow (bot_cy, -1), bot_cy - ART_CUP, len);
  cairo_restore (cr);

  /* Contorno de los dos extremos, más marcado a la derecha. */
  for (int k = 0; k < 2; k++) {
    cairo_new_path (cr);
    if (k == 0) cairo_arc (cr, 7.5, top_cy, GROOVE_R + ART_RIM_D, G_PI, 2 * G_PI);
    else        cairo_arc (cr, 7.5, bot_cy, GROOVE_R + ART_RIM_D, 0, G_PI);
    cairo_pattern_t *rim = cairo_pattern_create_linear (0, 0, 15, 0);
    cairo_pattern_add_color_stop_rgba (rim, 0, 0, 0, 0, ART_RIM_AL);
    cairo_pattern_add_color_stop_rgba (rim, 1, 0, 0, 0, ART_RIM_AR);
    cairo_set_source (cr, rim);
    cairo_set_line_width (cr, ART_RIM_W);
    cairo_stroke (cr);
    cairo_pattern_destroy (rim);
  }
}

/* ── pomo ─────────────────────────────────────────────────────────── */

/* Sombra: cápsula difuminada desplazada a la derecha (en la horizontal, hacia
 * abajo: la luz de Aqua viene de arriba). El alfa depende de la distancia al
 * eje: degradado horizontal en el tramo recto y radial en cada extremo. */
static void
thumb_shadow (cairo_t *cr, double y0, double len)
{
  const int n = G_N_ELEMENTS (ART_SH_STOPS);
  double cx = 7.5 + ART_SH_OX, dmax = ART_SH_D0 + ART_SH_DD * (n - 1), span = 2 * dmax;

  cairo_pattern_t *g = cairo_pattern_create_linear (cx - dmax, 0, cx + dmax, 0);
  cairo_pattern_add_color_stop_rgba (g, 0.5, 0, 0, 0, ART_SH_STOPS[0]);
  for (int i = 0; i < n; i++) {
    double d = ART_SH_D0 + ART_SH_DD * i;
    cairo_pattern_add_color_stop_rgba (g, 0.5 - d / span, 0, 0, 0, ART_SH_STOPS[i]);
    cairo_pattern_add_color_stop_rgba (g, 0.5 + d / span, 0, 0, 0, ART_SH_STOPS[i]);
  }
  paint_clipped (cr, g, y0 + 6.5, len - 13);

  for (int k = 0; k < 2; k++) {
    double cy = k == 0 ? y0 + 6.5 : y0 + len - 6.5;
    cairo_pattern_t *rg = cairo_pattern_create_radial (cx, cy, 0, cx, cy, dmax);
    cairo_pattern_add_color_stop_rgba (rg, 0, 0, 0, 0, ART_SH_STOPS[0]);
    for (int i = 0; i < n; i++)
      cairo_pattern_add_color_stop_rgba (rg, (ART_SH_D0 + ART_SH_DD * i) / dmax,
                                         0, 0, 0, ART_SH_STOPS[i]);
    cairo_pattern_set_extend (rg, CAIRO_EXTEND_NONE);
    if (k == 0) paint_clipped (cr, rg, y0 - 12, 18.5);
    else        paint_clipped (cr, rg, y0 + len - 6.5, 18.5);
  }
}

/* Moteado: el color claro del cuerpo enmascarado por la tesela de 16 filas,
 * repetida desde `anchor`, solo entre ya e yb. */
static void
mottle (cairo_t *cr, double anchor, double ya, double yb)
{
  if (yb <= ya) return;   /* pomo de menos de 20 filas: sin cuerpo */
  cairo_pattern_t *w = cairo_pattern_create_linear (0, anchor, 0, anchor + 16);
  for (int i = 0; i < 16; i++)
    cairo_pattern_add_color_stop_rgba (w, (i + 0.5) / 16.0, 0, 0, 0, ART_MOTTLE_W[i]);
  cairo_pattern_set_extend (w, CAIRO_EXTEND_REPEAT);
  cairo_save (cr);
  cairo_rectangle (cr, 0, ya, 15, yb - ya);
  cairo_clip (cr);
  cairo_pattern_t *c = rgb_profile (ART_BODY_C, 11, 2, 13);
  cairo_set_source (cr, c);
  cairo_mask (cr, w);
  cairo_restore (cr);
  cairo_pattern_destroy (c);
  cairo_pattern_destroy (w);
}

/* Bezier de un arco de circunferencia; ángulos en rad, 0 = hacia el extremo
 * del pomo (arriba), positivos hacia la derecha. */
static void
arc_ctrl (double cx, double cy, double r, double a0, double a1, double p[4][2])
{
  double k = 4.0 / 3.0 * tan ((a1 - a0) / 4.0) * r;
  p[0][0] = cx + r * sin (a0);  p[0][1] = cy - r * cos (a0);
  p[3][0] = cx + r * sin (a1);  p[3][1] = cy - r * cos (a1);
  p[1][0] = p[0][0] + k * cos (a0);  p[1][1] = p[0][1] + k * sin (a0);
  p[2][0] = p[3][0] - k * cos (a1);  p[2][1] = p[3][1] - k * sin (a1);
}

static const double *
mesh_node (int ring, int ang)
{
  return ART_MESH_NODE[ring == 0 ? 0 : 1 + (ring - 1) * ART_MESH_NA + ang];
}

/* Malla de degradado polar de un casquete: el sombreado del gel se curva
 * alrededor del semicírculo (bandas concéntricas, como en Tiger). flip = -1
 * da el casquete inferior. */
static cairo_pattern_t *
cap_mesh (double cx, double cy, double flip)
{
  cairo_pattern_t *m = cairo_pattern_create_mesh ();
  const int nr = G_N_ELEMENTS (ART_MESH_R);
#define PT(p) (p)[0], cy + flip * ((p)[1] - cy)
  const double center[2] = { cx, cy };
  for (int i = 0; i < nr - 1; i++) {
    double r0 = ART_MESH_R[i], r1 = ART_MESH_R[i + 1];
    for (int j = 0; j < ART_MESH_NA - 1; j++) {
      double a0 = (ART_MESH_A0 + j * ART_MESH_DA) * G_PI / 180.0;
      double a1 = (ART_MESH_A0 + (j + 1) * ART_MESH_DA) * G_PI / 180.0;
      double o[4][2], in[4][2];
      arc_ctrl (cx, cy, r1, a0, a1, o);
      if (r0 > 0) arc_ctrl (cx, cy, r0, a0, a1, in);
      cairo_mesh_pattern_begin_patch (m);
      cairo_mesh_pattern_move_to (m, PT (r0 > 0 ? in[0] : center));
      cairo_mesh_pattern_line_to (m, PT (o[0]));
      cairo_mesh_pattern_curve_to (m, PT (o[1]), PT (o[2]), PT (o[3]));
      if (r0 > 0) {
        cairo_mesh_pattern_line_to (m, PT (in[3]));
        cairo_mesh_pattern_curve_to (m, PT (in[2]), PT (in[1]), PT (in[0]));
      } else {
        cairo_mesh_pattern_line_to (m, PT (center));
        cairo_mesh_pattern_line_to (m, PT (center));
      }
      const double *c[4] = { mesh_node (i, j), mesh_node (i + 1, j),
                             mesh_node (i + 1, j + 1), mesh_node (i, j + 1) };
      for (int k = 0; k < 4; k++)
        cairo_mesh_pattern_set_corner_color_rgba (m, k, c[k][0], c[k][1], c[k][2], c[k][3]);
      cairo_mesh_pattern_end_patch (m);
    }
  }
#undef PT
  return m;
}

/* `tile`: fila donde arranca la tesela del cuerpo (fija en el canal → parallax). */
static void
draw_thumb (cairo_t *cr, double y0, double len, double tile)
{
  thumb_shadow (cr, y0, len);

  capsule (cr, 1, y0, 13, len);                        /* anillo de contorno */
  cairo_pattern_t *ring = rgb_profile (ART_RING, 13, 1, 14);
  cairo_set_source (cr, ring);
  cairo_fill (cr);
  cairo_pattern_destroy (ring);

  cairo_save (cr);                                     /* cuerpo de gel */
  capsule (cr, 2, y0 + 1, 11, len - 2);
  cairo_clip (cr);
  cairo_pattern_t *body = rgb_profile (ART_BODY_B, 11, 2, 13);
  cairo_set_source (cr, body);
  cairo_paint (cr);
  cairo_pattern_destroy (body);
  mottle (cr, y0 + 10, y0, y0 + 10);                   /* remate de arriba: fijo */
  mottle (cr, tile, y0 + 10, y0 + len - 10);           /* cuerpo */
  mottle (cr, y0 + len - 10, y0 + len - 10, y0 + len); /* remate de abajo: fijo */
  cairo_restore (cr);

  /* Casquetes: la malla cubre también 1,1 px por fuera del contorno, donde
   * Tiger tiene el halo de antialias de su arte reescalado. */
  for (int k = 0; k < 2; k++) {
    cairo_save (cr);
    capsule (cr, 1 - 1.1, y0 - 1.1, 13 + 2.2, len + 2.2);
    cairo_clip (cr);
    cairo_pattern_t *m = k == 0 ? cap_mesh (7.5, y0 + 6.5, 1)
                                : cap_mesh (7.5, y0 + len - 6.5, -1);
    cairo_set_source (cr, m);
    cairo_paint (cr);
    cairo_pattern_destroy (m);
    cairo_restore (cr);
  }
}

/* ── flechas ──────────────────────────────────────────────────────── */

static void
draw_arrows (cairo_t *cr, double len, AquaArtPress press)
{
  double y0 = len - AQUA_ART_ARROWS;
  fill_rect (cr, gray_profile (ART_SEPAR, 15, 0), 0, y0 + 15, 15, 1);
  /* Pulsada: sin referencia de Tiger, un oscurecido sutil del botón. */
  if (press == AQUA_ART_PRESS_UP) {
    cairo_set_source_rgba (cr, 0, 0, 0, 0.15);
    cairo_rectangle (cr, 0, y0, 15, 15);
    cairo_fill (cr);
  } else if (press == AQUA_ART_PRESS_DOWN) {
    cairo_set_source_rgba (cr, 0, 0, 0, 0.15);
    cairo_rectangle (cr, 0, y0 + 16, 15, 16);
    cairo_fill (cr);
  }
  /* ▲ y su espejo ▼ respecto al centro del separador (y0 + 15,5). */
  for (int k = 0; k < 2; k++) {
    double ya = k == 0 ? y0 + ART_TRI_AY : y0 + 31 - ART_TRI_AY;
    double yb = k == 0 ? y0 + ART_TRI_BY : y0 + 31 - ART_TRI_BY;
    cairo_new_path (cr);
    cairo_move_to (cr, ART_TRI_AX, ya);
    cairo_line_to (cr, ART_TRI_AX + ART_TRI_HW, yb);
    cairo_line_to (cr, ART_TRI_AX - ART_TRI_HW, yb);
    cairo_close_path (cr);
    cairo_pattern_t *g = gray_profile (ART_TRI_G, 7, 4);
    cairo_set_source (cr, g);
    cairo_fill (cr);
    cairo_pattern_destroy (g);
  }
}

/* ── API ──────────────────────────────────────────────────────────── */

void
aqua_art_draw (cairo_t *cr, double len, double thumb_y,
                   double thumb_len, AquaArtPress press)
{
  cairo_save (cr);
  cairo_set_line_cap (cr, CAIRO_LINE_CAP_ROUND);
  draw_body (cr, len, AQUA_ART_ARROWS);
  if (thumb_len > 0)
    draw_thumb (cr, thumb_y, thumb_len, AQUA_ART_THUMB_TOP + 10);
  draw_arrows (cr, len, press);
  cairo_restore (cr);
}

void
aqua_art_draw_thumb (cairo_t *cr, double thumb_y, double thumb_len)
{
  cairo_save (cr);
  draw_thumb (cr, thumb_y, thumb_len, thumb_y + 10);   /* sin canal: tesela del pomo */
  cairo_restore (cr);
}

void
aqua_art_draw_trough (cairo_t *cr, double len)
{
  cairo_save (cr);
  cairo_set_line_cap (cr, CAIRO_LINE_CAP_ROUND);
  draw_body (cr, len, TOP_PIECE);
  cairo_restore (cr);
}

void
aqua_art_transpose (cairo_t *cr)
{
  cairo_matrix_t t;
  cairo_matrix_init (&t, 0, 1, 1, 0, 0, 0);   /* (x, y) → (y, x) */
  cairo_transform (cr, &t);
}
