/* classic-visualizer.c — los efectos clásicos del visualizador
 * (src/Widgets/Visualizer.vala): los del clon de iTunes 7 del autor
 * (~/Proyectos/itunes/main, src/visualizer.c), en cairo puro.
 *
 * Doce estilos (túnel, rayos, estallido, espectro, onda, espectrograma,
 * estrellas, Lissajous, flor polar, rejilla, fuego, círculos) y seis paletas,
 * con disolvencia al cambiar y un núcleo que late con la música; en el centro
 * se turnan Tux, el logo de la distro, la carátula y la cabeza de GNU.
 *
 * Sin OpenGL: es el respaldo de projectM (Preferencias › Apariencia, y cuando
 * projectM no arranca). Los estilos y su dibujo se copian del clon tal cual;
 * cambian la entrada (10 bandas 0..1 que da BeatBox en cada paso de ~33 ms),
 * el logo de la distro (tema de iconos de GTK) y la carátula (la pone
 * BeatBox). Las opciones vis.* del clon quedan en sus valores por omisión. */
#include <gtk/gtk.h>
#include <math.h>
#include <string.h>

typedef struct _BbClassicVis BbClassicVis;

#define N_BANDS 10
#define N_RINGS 14            /* concentric rings of the tunnel */


/* Visualization styles. The user toggles with a double click and, if not
 * toca nada, rotan solos cada ~22 s para dar variedad. */
typedef enum {
  VIS_STYLE_TUNNEL = 0,   /* radial tunnel of rings (the original) */
  VIS_STYLE_BARS,         /* barras de espectro radiales (rayos) */
  VIS_STYLE_BURST,        /* rotating burst of petals/particles */
  VIS_STYLE_SPECTRUM,     /* classic mirrored bars (Audacious style) */
  VIS_STYLE_WAVE,         /* osciloscopio / forma de onda */
  VIS_STYLE_SPECTROGRAM,  /* cascada de espectro (voiceprint) */
  VIS_STYLE_STARS,        /* campo de estrellas a velocidad-warp */
  VIS_STYLE_LISSAJOUS,    /* curva de Lissajous (osciloscopio XY) */
  VIS_STYLE_POLAR,        /* flor/onda radial (espectro polar relleno) */
  VIS_STYLE_GRID,         /* rejilla en perspectiva tipo synthwave */
  VIS_STYLE_FIRE,         /* llamas ascendentes que laten con la música */
  VIS_STYLE_CIRCLES,      /* círculos concéntricos pulsantes por banda */
  VIS_N_STYLES
} VisStyle;

#define SPEC_HIST_W 128   /* spectrogram history columns */

struct _BbClassicVis {
  double     phase;          /* accumulated rotation/displacement */
  float      smooth[N_BANDS]; /* magnitudes suavizadas */
  float      energy;          /* smoothed global energy (0..1) */
  cairo_surface_t *logo_mask; /* Tux as an A8 mask (cached) */
  gboolean    logo_tried;
  cairo_surface_t *distro_surf; /* logo de la distro (color, ARGB32), cacheado */
  gboolean    distro_tried;
  cairo_surface_t *gnu_mask; /* A8 mask of the GNU logo (white contour, like Tux) */
  gboolean    gnu_tried;
  cairo_surface_t *art_surf; /* now-playing cover art (color, ARGB32), set by BeatBox */
  VisStyle    style;         /* current style */
  VisStyle    prev_style;    /* outgoing style during a transition */
  double      transition;    /* 0..1: fade progress to the current style (1 = settled) */
  int         theme;         /* color palette index (VIS_THEMES) */
  gboolean    auto_switch;   /* styles and palettes change by themselves */
  double      since_switch;  /* seconds (approx) since the last change */
  double      switch_interval; /* seconds until next random style switch */
  double      logo_clock;    /* cyclic clock (s) for the logo fade */
  float       spec_hist[SPEC_HIST_W][N_BANDS];
  int         spec_head;     /* index of the most recent column */
  /* Set from Preferences › Visualizer (bb_classic_vis_set_params / _set_masks) */
  double      speed;         /* 1 = the motion the effects were made for */
  double      transition_s;  /* seconds of the fade between two effects */
  double      interval_s;    /* seconds between automatic changes */
  gboolean    show_logos;    /* Tux, the distro, the cover and GNU take turns in the middle */
  guint       style_mask;    /* bit n: style n takes part in the changes */
  guint       theme_mask;    /* bit n: palette n takes part in the changes */
  double      spec_clock;    /* the spectrogram gets a column every ~33 ms, whatever the frame rate */
};

/* Convert HSV→RGB. h in [0,1). Reusable core. */
static void
hsv_to_rgb (double hue, double s, double v, double *r, double *g, double *b)
{
  hue = hue - floor (hue);          /* envolver a [0,1) */
  double h6 = hue * 6.0;
  int i = (int) floor (h6);
  double f = h6 - i;
  double p = v * (1.0 - s);
  double q = v * (1.0 - s * f);
  double tt = v * (1.0 - s * (1.0 - f));
  switch (i % 6) {
    case 0: *r = v;  *g = tt; *b = p;  break;
    case 1: *r = q;  *g = v;  *b = p;  break;
    case 2: *r = p;  *g = v;  *b = tt; break;
    case 3: *r = p;  *g = q;  *b = v;  break;
    case 4: *r = tt; *g = p;  *b = v;  break;
    default:*r = v;  *g = p;  *b = q;  break;
  }
}

/* Paletas de color del visualizador. Cada tema define un rango de matiz
 * (base + width), a saturation, and a background tint. Some span a wide
 * range of the color wheel (rainbow), others are monochrome. */
typedef struct {
  const char *name;
  double hue_base;   /* matiz inicial (0..1) */
  double hue_span;   /* how far the hue travels with t (may be >1 = several turns) */
  double sat;        /* saturation */
  double bg_r, bg_g, bg_b;  /* tint of the central background gradient */
} VisTheme;

static const VisTheme VIS_THEMES[] = {
  /* Amber/gold (the original): red→yellow, warm background. */
  { "Amber",     0.02, 0.12, 0.95, 0.10, 0.05, 0.00 },
  /* Ocean: cyan→blue, cool background. */
  { "Ocean",     0.45, 0.18, 0.90, 0.00, 0.05, 0.12 },
  /* Neon: magenta→violet, purple background. */
  { "Neon",      0.80, 0.20, 1.00, 0.10, 0.00, 0.12 },
  /* Bosque: verde→lima, fondo verde oscuro. */
  { "Bosque",    0.28, 0.16, 0.85, 0.02, 0.10, 0.03 },
  /* Rainbow: spans the ENTIRE color wheel (wide range). */
  { "Rainbow",   0.00, 1.00, 0.95, 0.04, 0.04, 0.06 },
  /* Atardecer: rosa→naranja→amarillo. */
  { "Atardecer", 0.92, 0.22, 0.92, 0.10, 0.03, 0.04 },
};
#define VIS_N_THEMES ((int) G_N_ELEMENTS (VIS_THEMES))

/* Current theme's color for a parameter t∈[0,1] and a given brightness. */
static void
vis_color (BbClassicVis *self, double t, double bright, double *r, double *g, double *b)
{
  const VisTheme *th = &VIS_THEMES[self->theme % VIS_N_THEMES];
  double hue = th->hue_base + th->hue_span * CLAMP (t, 0.0, 1.0);
  hsv_to_rgb (hue, th->sat, CLAMP (bright, 0.0, 1.0), r, g, b);
}

/* Magnitud interpolada del espectro para t∈[0,1) sobre las N_BANDS
 * bands, to draw more "bars"/samples than real bands. */
static double
band_at (BbClassicVis *self, double t)
{
  t = CLAMP (t, 0.0, 0.99999);
  double bp = t * N_BANDS;
  int b0 = (int) bp;
  int b1 = MIN (b0 + 1, N_BANDS - 1);
  double f = bp - b0;
  return self->smooth[b0] * (1.0 - f) + self->smooth[b1] * f;
}

/* ---- Style 1: TUNNEL of concentric rings (the original) ---- */
static void
draw_tunnel (BbClassicVis *self, cairo_t *cr, int w, int h,
             double cx, double cy, double maxr, double e)
{
  for (int ring = 0; ring < N_RINGS; ++ring) {
    double base = fmod (ring / (double) N_RINGS + self->phase * 0.06, 1.0);
    double rr = base * base * maxr;
    if (rr < 6) continue;
    double fade = (0.45 + 0.55 * (1.0 - base)) * (0.5 + 0.7 * e);
    double bright = CLAMP (fade, 0.0, 1.0);

    const int SEG = 96;
    cairo_new_path (cr);
    for (int sgi = 0; sgi <= SEG; ++sgi) {
      double ang = (sgi / (double) SEG) * 2.0 * G_PI + self->phase * 0.5;
      double bf = (ang / (2.0 * G_PI)) * N_BANDS;
      int bi = ((int) bf) % N_BANDS;
      double m = self->smooth[bi];
      double def = 1.0 + m * 0.6 * (0.4 + 0.6 * base);
      double rad = rr * def;
      double x = cx + cos (ang) * rad;
      double y = cy + sin (ang) * rad;
      if (sgi == 0) cairo_move_to (cr, x, y);
      else          cairo_line_to (cr, x, y);
    }
    cairo_close_path (cr);

    double r, g, b;
    vis_color (self, 0.2 + 0.5 * base, bright, &r, &g, &b);
    cairo_set_source_rgba (cr, r, g, b, 0.18 * bright);
    cairo_set_line_width (cr, 6.0 + 6.0 * bright);
    cairo_stroke_preserve (cr);
    cairo_set_source_rgba (cr, r, g, b, CLAMP (0.85 * bright + 0.15, 0.0, 1.0));
    cairo_set_line_width (cr, 1.5 + 2.0 * bright);
    cairo_stroke (cr);
  }
  (void) w; (void) h;
}

/* ---- Estilo 2: BARRAS de espectro radiales (rayos que laten) ----
 * Each ray grows from an inner ring outward according to its band,
 * con una punta luminosa. El conjunto gira lentamente. */
static void
draw_bars (BbClassicVis *self, cairo_t *cr, int w, int h,
           double cx, double cy, double maxr, double e)
{
  (void) w; (void) h;
  const int RAYS = N_BANDS * 4;
  double inner = maxr * 0.10;
  double rot = self->phase * 0.25;
  cairo_set_line_cap (cr, CAIRO_LINE_CAP_ROUND);
  for (int i = 0; i < RAYS; ++i) {
    double ang = (i / (double) RAYS) * 2.0 * G_PI + rot;
    double bpos = (i / (double) RAYS) * N_BANDS;
    int b0 = ((int) bpos) % N_BANDS;
    int b1 = (b0 + 1) % N_BANDS;
    double frac = bpos - floor (bpos);
    double m = self->smooth[b0] * (1.0 - frac) + self->smooth[b1] * frac;

    double len = inner + (maxr * 0.78) * CLAMP (m, 0.0, 1.0);
    double x0 = cx + cos (ang) * inner;
    double y0 = cy + sin (ang) * inner;
    double x1 = cx + cos (ang) * len;
    double y1 = cy + sin (ang) * len;

    double bright = CLAMP (0.35 + 0.65 * m + 0.2 * e, 0.0, 1.0);
    double r, g, b;
    vis_color (self, 0.1 + 0.7 * m, bright, &r, &g, &b);

    cairo_set_source_rgba (cr, r, g, b, 0.16 * bright);
    cairo_set_line_width (cr, 9.0);
    cairo_move_to (cr, x0, y0); cairo_line_to (cr, x1, y1); cairo_stroke (cr);
    cairo_set_source_rgba (cr, r, g, b, 0.9 * bright);
    cairo_set_line_width (cr, 3.0);
    cairo_move_to (cr, x0, y0); cairo_line_to (cr, x1, y1); cairo_stroke (cr);

    cairo_set_source_rgba (cr, 1.0, 0.96, 0.8, 0.9 * bright);
    cairo_arc (cr, x1, y1, 2.2 + 2.0 * m, 0, 2 * G_PI);
    cairo_fill (cr);
  }
}

/* ---- Style 3: rotating petal BURST ----
 * Petal-like curves emanating from the center, one per band and per "arm",
 * rotating in alternating directions → kaleidoscopic effect. */
static void
draw_burst (BbClassicVis *self, cairo_t *cr, int w, int h,
            double cx, double cy, double maxr, double e)
{
  (void) w; (void) h;
  const int ARMS = 6;
  for (int arm = 0; arm < ARMS; ++arm) {
    double base_ang = (arm / (double) ARMS) * 2.0 * G_PI
                    + self->phase * 0.3 * (arm % 2 ? 1.0 : -1.0);
    for (int bnd = 0; bnd < N_BANDS; ++bnd) {
      double m = self->smooth[bnd];
      if (m < 0.02) continue;
      double reach = maxr * (0.15 + 0.8 * CLAMP (m, 0.0, 1.0));
      double spread = (bnd / (double) N_BANDS) * 0.9;
      double a1 = base_ang + spread;
      double curl = 0.6 + 0.5 * sin (self->phase + bnd);

      double bright = CLAMP (0.3 + 0.7 * m + 0.15 * e, 0.0, 1.0);
      double r, g, b;
      vis_color (self, 0.05 + 0.8 * (bnd / (double) N_BANDS), bright, &r, &g, &b);

      double ex = cx + cos (a1) * reach;
      double ey = cy + sin (a1) * reach;
      double c1x = cx + cos (base_ang) * reach * 0.4;
      double c1y = cy + sin (base_ang) * reach * 0.4;
      double c2x = cx + cos (a1 + curl) * reach * 0.7;
      double c2y = cy + sin (a1 + curl) * reach * 0.7;

      cairo_new_path (cr);
      cairo_move_to (cr, cx, cy);
      cairo_curve_to (cr, c1x, c1y, c2x, c2y, ex, ey);
      cairo_set_line_cap (cr, CAIRO_LINE_CAP_ROUND);
      cairo_set_source_rgba (cr, r, g, b, 0.14 * bright);
      cairo_set_line_width (cr, 10.0 * (0.4 + m));
      cairo_stroke_preserve (cr);
      cairo_set_source_rgba (cr, r, g, b, 0.85 * bright);
      cairo_set_line_width (cr, 2.5 * (0.5 + m));
      cairo_stroke (cr);

      cairo_set_source_rgba (cr, 1.0, 0.95, 0.78, 0.85 * bright);
      cairo_arc (cr, ex, ey, 2.0 + 2.5 * m, 0, 2 * G_PI);
      cairo_fill (cr);
    }
  }
}

/* ---- Style 4: classic SPECTRUM (mirrored bars) ----
 * Vertical bars across the width of the screen that grow from the
 * center upward and downward (mirrored), with a luminous tip.
 * It's the typical "spectrum analyzer" look (Audacious/XMMS). */
static void
draw_spectrum (BbClassicVis *self, cairo_t *cr, int w, int h,
               double cx, double cy, double maxr, double e)
{
  (void) cx; (void) maxr;
  const int BARS = 56;
  const double gap = 2.0;
  double bw = (w - (BARS + 1) * gap) / (double) BARS;
  if (bw < 1.0) bw = 1.0;
  double midy = cy;
  double maxbar = h * 0.40;
  for (int i = 0; i < BARS; ++i) {
    double t = (i + 0.5) / BARS;
    double m = CLAMP (band_at (self, t), 0.0, 1.0);
    double bh = maxbar * pow (m, 0.85);
    double x = gap + i * (bw + gap);
    double bright = CLAMP (0.40 + 0.60 * m + 0.15 * e, 0.0, 1.0);
    double r, g, b;
    vis_color (self, t, bright, &r, &g, &b);

    /* Bar going up (more vivid) and reflection going down (dimmer). */
    cairo_set_source_rgba (cr, r, g, b, 0.92 * bright);
    cairo_rectangle (cr, x, midy - bh, bw, bh);
    cairo_fill (cr);
    cairo_set_source_rgba (cr, r, g, b, 0.40 * bright);
    cairo_rectangle (cr, x, midy + 1, bw, bh * 0.85);
    cairo_fill (cr);
    /* Punta blanca. */
    if (bh > 3) {
      cairo_set_source_rgba (cr, 1.0, 1.0, 1.0, 0.75 * bright);
      cairo_rectangle (cr, x, midy - bh - 2.0, bw, 2.5);
      cairo_fill (cr);
    }
  }
}

/* ---- Estilo 5: WAVE / osciloscopio ----
 * Sintetizamos una forma de onda sumando senos cuya amplitud viene de
 * each spectrum band; it shifts with the phase. Gives a "scope"-like
 * line that reacts to the music. */
static void
draw_wave (BbClassicVis *self, cairo_t *cr, int w, int h,
           double cx, double cy, double maxr, double e)
{
  (void) cx; (void) maxr;
  double amp = h * 0.32 * (0.35 + e);
  double r, g, b;
  vis_color (self, 0.5, CLAMP (0.55 + 0.55 * e, 0.0, 1.0), &r, &g, &b);

  for (int pass = 0; pass < 2; ++pass) {
    /* pass 0: main line; pass 1: mirrored, dimmer echo. */
    double sgn = pass ? -1.0 : 1.0;
    cairo_new_path (cr);
    for (int x = 0; x <= w; x += 2) {
      double u = x / (double) w;
      double s = 0.0, wsum = 0.0;
      for (int bnd = 0; bnd < N_BANDS; ++bnd) {
        double freq = 2.0 + bnd * 2.3;
        double m = self->smooth[bnd];
        s += m * sin (2.0 * G_PI * freq * u + self->phase * (1.0 + 0.15 * bnd));
        wsum += 0.6 + m;
      }
      double y = cy + sgn * amp * (s / (wsum > 0 ? wsum : 1.0));
      if (x == 0) cairo_move_to (cr, x, y);
      else        cairo_line_to (cr, x, y);
    }
    cairo_set_line_join (cr, CAIRO_LINE_JOIN_ROUND);
    cairo_set_source_rgba (cr, r, g, b, pass ? 0.10 : 0.18);
    cairo_set_line_width (cr, pass ? 6.0 : 11.0);
    cairo_stroke_preserve (cr);
    cairo_set_source_rgba (cr, r, g, b, pass ? 0.35 : 0.95);
    cairo_set_line_width (cr, pass ? 1.4 : 2.4);
    cairo_stroke (cr);
  }
}

/* ---- Estilo 6: SPECTROGRAM / voiceprint (cascada) ----
 * Each column is a time slice; the rows are frequency
 * (band 0 = bass at the bottom). Color/brightness encodes the magnitude. The
 * history scrolls: the most recent on the right. */
static void
draw_spectrogram (BbClassicVis *self, cairo_t *cr, int w, int h,
                  double cx, double cy, double maxr, double e)
{
  (void) cx; (void) cy; (void) maxr; (void) e;
  double colw = w / (double) SPEC_HIST_W;
  for (int sx = 0; sx < SPEC_HIST_W; ++sx) {
    /* sx=0 (left) = oldest; sx=W-1 (right) = newest. */
    int age = (SPEC_HIST_W - 1) - sx;
    int idx = ((self->spec_head - age) % SPEC_HIST_W + SPEC_HIST_W) % SPEC_HIST_W;
    double x = sx * colw;

    /* Vertical gradient of the column: one stop per band (bass
     * low → treble high). Cheap and smooth. */
    cairo_pattern_t *grad = cairo_pattern_create_linear (0, h, 0, 0);
    for (int bnd = 0; bnd < N_BANDS; ++bnd) {
      double m = CLAMP (self->spec_hist[idx][bnd], 0.0, 1.0);
      double off = bnd / (double) (N_BANDS - 1);
      double r, g, b;
      vis_color (self, off, CLAMP (0.15 + 0.95 * m, 0.0, 1.0), &r, &g, &b);
      cairo_pattern_add_color_stop_rgba (grad, off, r, g, b,
                                         CLAMP (0.12 + 0.9 * m, 0.0, 1.0));
    }
    cairo_set_source (cr, grad);
    cairo_rectangle (cr, x, 0, colw + 1.0, h);
    cairo_fill (cr);
    cairo_pattern_destroy (grad);
  }
}

/* ---- Estilo 7: STARFIELD (velocidad warp) ----
 * Particles flying out from the center accelerating with the energy;
 * each leaves a short trail. Together they evoke hyperspace travel. */
static void
draw_stars (BbClassicVis *self, cairo_t *cr, int w, int h,
            double cx, double cy, double maxr, double e)
{
  (void) w; (void) h;
  const int N = 150;
  cairo_set_line_cap (cr, CAIRO_LINE_CAP_ROUND);
  for (int i = 0; i < N; ++i) {
    double a    = i * 2.39996323;                 /* golden angle → uniform spread */
    double seed = i * 0.61803398875;
    seed -= floor (seed);
    double sp = 0.12 + seed * 0.5;                /* velocidad por estrella */
    double depth = fmod (self->phase * sp * (0.5 + e) + seed * 7.0, 1.0);
    double rad = depth * depth * maxr;
    double ang = a + self->phase * 0.05;
    double x = cx + cos (ang) * rad;
    double y = cy + sin (ang) * rad;

    double m = self->smooth[i % N_BANDS];
    double bright = CLAMP (depth * (0.5 + 0.8 * e) + 0.4 * m, 0.0, 1.0);
    double sz = 0.6 + depth * 2.6 + 2.5 * m;
    double r, g, b;
    vis_color (self, depth, bright, &r, &g, &b);

    double px = cx + cos (ang) * rad * 0.90;
    double py = cy + sin (ang) * rad * 0.90;
    cairo_set_source_rgba (cr, r, g, b, 0.5 * bright);
    cairo_set_line_width (cr, sz * 0.8);
    cairo_move_to (cr, px, py); cairo_line_to (cr, x, y); cairo_stroke (cr);
    cairo_set_source_rgba (cr, 1.0, 1.0, 1.0, 0.85 * bright);
    cairo_arc (cr, x, y, sz * 0.6, 0, 2 * G_PI); cairo_fill (cr);
  }
}

/* ---- Estilo 8: LISSAJOUS (osciloscopio XY) ----
 * Parametric curve x=sin(a·t+φ), y=sin(b·t); a/b and the amplitude
 * modulan con el espectro. Recuerda al modo "XY" de un osciloscopio. */
static void
draw_lissajous (BbClassicVis *self, cairo_t *cr, int w, int h,
                double cx, double cy, double maxr, double e)
{
  (void) w; (void) h;
  double R = maxr * (0.30 + 0.45 * e);
  double a = 3.0 + self->smooth[2] * 4.0;
  double b = 2.0 + self->smooth[6] * 4.0;
  double r, g, bl;
  vis_color (self, 0.5, CLAMP (0.55 + 0.5 * e, 0.0, 1.0), &r, &g, &bl);
  const int N = 400;
  for (int pass = 0; pass < 2; ++pass) {
    cairo_new_path (cr);
    for (int i = 0; i <= N; ++i) {
      double t = (i / (double) N) * 2.0 * G_PI;
      double mod = 1.0 + 0.25 * self->smooth[i % N_BANDS];
      double x = cx + R * mod * sin (a * t + self->phase);
      double y = cy + R * mod * sin (b * t);
      if (i == 0) cairo_move_to (cr, x, y);
      else        cairo_line_to (cr, x, y);
    }
    cairo_set_line_join (cr, CAIRO_LINE_JOIN_ROUND);
    cairo_set_source_rgba (cr, r, g, bl, pass ? 0.95 : 0.16);
    cairo_set_line_width (cr, pass ? 2.0 : 9.0);
    cairo_stroke (cr);
  }
}

/* ---- Estilo 9: POLAR (flor/onda radial rellena) ----
 * A closed contour whose radius per angle comes from the corresponding
 * band: a "blob" that pulses and rotates. Translucent fill +
 * borde luminoso. */
static void
draw_polar (BbClassicVis *self, cairo_t *cr, int w, int h,
            double cx, double cy, double maxr, double e)
{
  (void) w; (void) h;
  const int N = 240;
  double base = maxr * 0.18;
  double amp  = maxr * 0.55;
  cairo_new_path (cr);
  for (int i = 0; i <= N; ++i) {
    double t = i / (double) N;
    double ang = t * 2.0 * G_PI + self->phase * 0.4;
    /* symmetric radius: we use a folded t so the contour closes smoothly */
    double tt = t < 0.5 ? t * 2.0 : (1.0 - t) * 2.0;
    double m = CLAMP (band_at (self, tt), 0.0, 1.0);
    double rad = base + amp * m;
    double x = cx + cos (ang) * rad;
    double y = cy + sin (ang) * rad;
    if (i == 0) cairo_move_to (cr, x, y);
    else        cairo_line_to (cr, x, y);
  }
  cairo_close_path (cr);
  double r, g, b;
  vis_color (self, 0.4, CLAMP (0.5 + 0.5 * e, 0.0, 1.0), &r, &g, &b);
  cairo_set_source_rgba (cr, r, g, b, 0.25 + 0.25 * e);
  cairo_fill_preserve (cr);
  cairo_set_source_rgba (cr, r, g, b, 0.95);
  cairo_set_line_width (cr, 2.5);
  cairo_set_line_join (cr, CAIRO_LINE_JOIN_ROUND);
  cairo_stroke (cr);
}

/* ---- Estilo 10: GRID (rejilla en perspectiva, synthwave) ----
 * A grid receding toward a horizon; the horizontal lines
 * se desplazan hacia el espectador (scroll con la fase) y la malla
 * "breathes" with the energy. Retro-80s flavor. */
static void
draw_grid (BbClassicVis *self, cairo_t *cr, int w, int h,
           double cx, double cy, double maxr, double e)
{
  (void) maxr;
  double horizon = h * 0.42;
  double r, g, b;
  vis_color (self, 0.7, CLAMP (0.55 + 0.45 * e, 0.0, 1.0), &r, &g, &b);
  cairo_set_line_width (cr, 1.4);

  /* Horizontal lines: closer together near the horizon (perspective),
   * scrolling downward with the phase. */
  double scroll = fmod (self->phase * 0.5, 1.0);
  for (int i = 0; i < 18; ++i) {
    double k = (i + scroll) / 18.0;
    double yy = horizon + (h - horizon) * k * k;       /* k² → perspectiva */
    double alpha = CLAMP (0.15 + 0.7 * k, 0.0, 1.0);
    cairo_set_source_rgba (cr, r, g, b, alpha);
    cairo_move_to (cr, 0, yy); cairo_line_to (cr, w, yy); cairo_stroke (cr);
  }
  /* Vertical lines converging at the vanishing point (cx, horizon). */
  for (int i = -10; i <= 10; ++i) {
    double fx = cx + i * (w * 0.06);
    cairo_set_source_rgba (cr, r, g, b, 0.45);
    cairo_move_to (cr, cx + (fx - cx) * 0.02, horizon);
    cairo_line_to (cr, fx, h);
    cairo_stroke (cr);
  }
  /* Spectrum skyline above the horizon (symmetric bars). */
  int BARS = N_BANDS * 3;
  double bw = (double) w / BARS;
  for (int i = 0; i < BARS; ++i) {
    double t = (i + 0.5) / BARS;
    double m = CLAMP (band_at (self, t), 0.0, 1.0);
    double bh = horizon * 0.7 * pow (m, 0.8);
    double x = i * bw;
    double br, bg, bb;
    vis_color (self, t, CLAMP (0.5 + 0.5 * m, 0.0, 1.0), &br, &bg, &bb);
    cairo_set_source_rgba (cr, br, bg, bb, 0.85);
    cairo_rectangle (cr, x, horizon - bh, bw - 1.0, bh);
    cairo_fill (cr);
  }
  (void) cy;
}

/* ---- Estilo 11: FIRE — llamas que ascienden, laten con energía ----
 * Partículas de fuego que suben desde la base y se avivan con cada
 * golpe de graves. La altura y brillo siguen el espectro. */
static void
draw_fire (BbClassicVis *self, cairo_t *cr, int w, int h,
           double cx, double cy, double maxr, double e)
{
  (void) cx; (void) cy; (void) maxr;
  const int N_FLAMES = 80;
  double flame_h = h * 0.55 * (0.6 + 0.4 * e);
  for (int i = 0; i < N_FLAMES; ++i) {
    double t = (i + 0.5) / N_FLAMES;           /* 0..1 horizontal */
    double b = self->smooth[i % N_BANDS];
    double phase_off = fmod (t * 7.0 + self->phase * 2.0, 1.0);
    double rise = (1.0 - phase_off) * flame_h * (0.5 + 0.5 * b);
    double flicker = 0.85 + 0.15 * sin (self->phase * 12.0 + i * 1.7);
    double width = 4.0 + 12.0 * (1.0 - phase_off);
    double alpha = (1.0 - phase_off) * (0.3 + 0.7 * e) * flicker;
    double r, g, b0;
    vis_color (self, t * 0.15 + (1.0 - phase_off) * 0.08,
               CLAMP (0.6 + 0.4 * b, 0.0, 1.0), &r, &g, &b0);
    cairo_set_source_rgba (cr, r, g, b0, CLAMP (alpha, 0.0, 0.7));
    double x = (i / (double) N_FLAMES) * w;
    double y = h - rise;
    cairo_arc (cr, x, y, width * 0.5, 0, 2 * G_PI);
    cairo_fill (cr);
  }
}

/* ---- Estilo 12: CIRCLES — anillos concéntricos pulsantes ----
 * Cada banda del ecualizador dibuja un círculo de radio creciente,
 * con grosor y opacidad modulados por la energía de esa banda. */
static void
draw_circles (BbClassicVis *self, cairo_t *cr, int w, int h,
              double cx, double cy, double maxr, double e)
{
  (void) w; (void) h;
  double max_cr = maxr * 0.85;
  for (int i = 0; i < N_BANDS; ++i) {
    double m = self->smooth[i];
    if (m < 0.01) continue;
    double t = (i + 0.5) / N_BANDS;
    double radius = max_cr * (0.1 + 0.9 * m);
    double lw = 2.0 + 14.0 * m * (0.5 + 0.5 * e);
    double r, g, b;
    vis_color (self, t, CLAMP (0.4 + 0.6 * m, 0.0, 1.0), &r, &g, &b);
    cairo_set_source_rgba (cr, r, g, b, 0.25 + 0.55 * m);
    cairo_set_line_width (cr, lw);
    cairo_arc (cr, cx, cy, radius, 0, 2 * G_PI);
    cairo_stroke (cr);
    /* inner glow ring */
    cairo_set_source_rgba (cr, r, g, b, 0.08 * m);
    cairo_arc (cr, cx, cy, radius - lw * 0.5, 0, 2 * G_PI);
    cairo_fill (cr);
  }
}

/* Despacha al dibujo del estilo indicado. */
static void
vis_draw_style (BbClassicVis *self, VisStyle st, cairo_t *cr, int w, int h,
                double cx, double cy, double maxr, double e)
{
  switch (st) {
    case VIS_STYLE_BARS:        draw_bars        (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_BURST:       draw_burst       (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_SPECTRUM:    draw_spectrum    (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_WAVE:        draw_wave        (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_SPECTROGRAM: draw_spectrogram (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_STARS:       draw_stars       (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_LISSAJOUS:   draw_lissajous   (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_POLAR:       draw_polar       (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_GRID:        draw_grid        (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_FIRE:        draw_fire        (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_CIRCLES:     draw_circles     (self, cr, w, h, cx, cy, maxr, e); break;
    case VIS_STYLE_TUNNEL:
    default:                    draw_tunnel      (self, cr, w, h, cx, cy, maxr, e); break;
  }
}

/* How much central "core" suits each style: full in the radial ones
 * (tunnel/bars/burst/stars), faint in the flat ones (spectrum, wave,
 * spectrogram) where a central flash would get in the way. */
static double
style_core_factor (VisStyle st)
{
  switch (st) {
    case VIS_STYLE_SPECTRUM:
    case VIS_STYLE_WAVE:
    case VIS_STYLE_SPECTROGRAM: return 0.22;
    default:                    return 1.0;
  }
}

/* Suavizado tipo smoothstep para el fundido (acelera/desacelera). */
static inline double
smoothstep01 (double t)
{
  t = CLAMP (t, 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/* Carga (una vez) el logo de la distro en curso como surface a color.
 * Fuente: /etc/os-release LOGO=<icon-name> → tema de iconos → pixmap.
 * El logo es a COLOR (no silueta), así que lo pintamos tal cual, no como
 * máscara (a diferencia de Tux). Si no se encuentra, distro_surf queda NULL
 * y nunca se dibuja. */

/* Pixbuf RGB(A) → surface ARGB32 (premultiplicado, orden de bytes nativo). */
static cairo_surface_t *
surface_from_pixbuf (GdkPixbuf *pb)
{
  int tw = gdk_pixbuf_get_width (pb), th = gdk_pixbuf_get_height (pb);
  int n_ch = gdk_pixbuf_get_n_channels (pb);
  gboolean has_a = gdk_pixbuf_get_has_alpha (pb);
  int prs = gdk_pixbuf_get_rowstride (pb);
  const guchar *px = gdk_pixbuf_get_pixels (pb);

  cairo_surface_t *s = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, tw, th);
  cairo_surface_flush (s);
  int sstride = cairo_image_surface_get_stride (s);
  guchar *sdata = cairo_image_surface_get_data (s);
  for (int y = 0; y < th; ++y) {
    const guchar *srow = px + (gsize) y * prs;
    guint32 *drow = (guint32 *)(sdata + (gsize) y * sstride);
    for (int x = 0; x < tw; ++x) {
      const guchar *p = srow + x * n_ch;
      guint a = has_a ? p[3] : 0xFF;
      guint r = p[0] * a / 255, gg = p[1] * a / 255, bb = p[2] * a / 255;
      drow[x] = (a << 24) | (r << 16) | (gg << 8) | bb;   /* premult ARGB */
    }
  }
  cairo_surface_mark_dirty (s);
  return s;
}

static void
load_distro_logo (BbClassicVis *self)
{
  self->distro_tried = TRUE;
  g_autofree char *content = NULL;
  if (!g_file_get_contents ("/etc/os-release", &content, NULL, NULL))
    return;

  /* Sacar LOGO=... (o ID=... como respaldo). */
  g_autofree char *name = NULL;
  g_auto(GStrv) lines = g_strsplit (content, "\n", -1);
  for (int i = 0; lines[i]; ++i) {
    const char *l = lines[i];
    const char *key = NULL;
    if (g_str_has_prefix (l, "LOGO=")) key = l + 5;
    else if (!name && g_str_has_prefix (l, "ID=")) key = l + 3;
    if (key) {
      g_autofree char *v = g_strdup (key);
      g_strstrip (v);
      gsize n = strlen (v);
      if (n >= 2 && v[0] == '"' && v[n-1] == '"') { v[n-1] = '\0'; memmove (v, v+1, n-1); }
      if (*v) { g_free (name); name = g_strdup (v); }
      if (g_str_has_prefix (l, "LOGO=")) break;   /* LOGO gana sobre ID */
    }
  }
  if (!name || !*name)
    return;

  GdkPixbuf *pb = NULL;

  /* 1) tema de iconos de GTK */
  GtkIconPaintable *info = gtk_icon_theme_lookup_icon (
      gtk_icon_theme_get_for_display (gdk_display_get_default ()), name, NULL, 256, 1,
      GTK_TEXT_DIR_NONE, 0);
  if (info) {
    GFile *file = gtk_icon_paintable_get_file (info);   /* referencia nueva; NULL si no es un archivo */
    g_autofree char *p = file ? g_file_get_path (file) : NULL;
    g_clear_object (&file);
    if (p) pb = gdk_pixbuf_new_from_file_at_scale (p, 256, 256, TRUE, NULL);
    g_object_unref (info);
  }

  /* 2) respaldo: /usr/share/pixmaps/<name>.{svg,png} */
  if (!pb) {
    const char *exts[] = { ".svg", ".png", "" };
    for (int e = 0; !pb && e < 3; ++e) {
      g_autofree char *p = g_strdup_printf ("/usr/share/pixmaps/%s%s", name, exts[e]);
      if (g_file_test (p, G_FILE_TEST_EXISTS))
        pb = gdk_pixbuf_new_from_file_at_scale (p, 256, 256, TRUE, NULL);
    }
  }
  if (!pb)
    return;
  self->distro_surf = surface_from_pixbuf (pb);
  g_object_unref (pb);
}

/* Build an A8 luminance-inverted mask from a pixbuf (dark pixels → opaque),
 * so a black silhouette SVG renders as a white contour. Same recipe Tux uses;
 * factored so the GNU logo reuses it. Returns a new surface (caller caches). */
static cairo_surface_t *
vis_mask_from_pixbuf (GdkPixbuf *pb)
{
  int tw = gdk_pixbuf_get_width (pb), th = gdk_pixbuf_get_height (pb);
  if (tw <= 0 || th <= 0) return NULL;
  int n_ch = gdk_pixbuf_get_n_channels (pb);
  gboolean has_a = gdk_pixbuf_get_has_alpha (pb);
  int prs = gdk_pixbuf_get_rowstride (pb);
  const guchar *px = gdk_pixbuf_get_pixels (pb);

  cairo_surface_t *m = cairo_image_surface_create (CAIRO_FORMAT_A8, tw, th);
  cairo_surface_flush (m);
  int mstride = cairo_image_surface_get_stride (m);
  guchar *mdata = cairo_image_surface_get_data (m);
  for (int y = 0; y < th; ++y) {
    const guchar *srow = px + (gsize) y * prs;
    guchar *drow = mdata + (gsize) y * mstride;
    for (int x = 0; x < tw; ++x) {
      const guchar *p = srow + x * n_ch;
      guchar src_a = has_a ? p[n_ch - 1] : 0xFF;
      if (src_a < 16) { drow[x] = 0; continue; }
      int lum = (299 * p[0] + 587 * p[1] + 114 * p[2]) / 1000;
      drow[x] = (guchar)((255 - lum) * src_a / 255);
    }
  }
  cairo_surface_mark_dirty (m);
  return m;
}

/* A black silhouette SVG from BeatBox's resources as a white-contour A8 mask
 * (Tux, GNU). NULL if it can't be read. */
static cairo_surface_t *
load_mask (const char *resource)
{
  GdkPixbuf *pb = gdk_pixbuf_new_from_resource_at_scale (resource, 256, 256, TRUE, NULL);
  if (!pb) return NULL;
  cairo_surface_t *m = vis_mask_from_pixbuf (pb);
  g_object_unref (pb);
  return m;
}

typedef enum { IK_TUX, IK_DISTRO, IK_ART, IK_GNU } IconKind;

/* Paint a cached surface centred at (cx,cy), sized to ~22% of the screen and
 * pulsed by energy, at the given alpha. `as_mask` paints it white through its
 * A8 mask (Tux/GNU); otherwise it's a colour surface (distro/art). `fast`
 * picks nearest-neighbour scaling for the low-quality mode. */
static void
draw_one_icon (cairo_t *cr, cairo_surface_t *surf, gboolean as_mask,
               double cx, double cy, int w, int h, double e,
               double alpha, gboolean fast)
{
  if (!surf || alpha <= 0.0) return;
  int tw = cairo_image_surface_get_width (surf);
  int th = cairo_image_surface_get_height (surf);
  if (tw <= 0 || th <= 0) return;
  int icon_pct = 22;   /* vis.icon_size_pct */
  double target = MIN (w, h) * (icon_pct / 100.0) * (0.96 + 0.04 * e);
  double scale = target / MAX (tw, th);
  double dw = tw * scale, dh = th * scale;

  cairo_save (cr);
  cairo_translate (cr, cx - dw * 0.5, cy - dh * 0.5);
  cairo_scale (cr, scale, scale);
  if (as_mask) {
    cairo_set_source_rgba (cr, 1, 1, 1, 0.92 * alpha);
    cairo_mask_surface (cr, surf, 0, 0);
  } else {
    cairo_set_source_surface (cr, surf, 0, 0);
    if (fast)
      cairo_pattern_set_filter (cairo_get_source (cr), CAIRO_FILTER_NEAREST);
    cairo_paint_with_alpha (cr, alpha);
  }
  cairo_restore (cr);
}

/* Draw the rotating centre icon: Tux, the distro's logo, the cover and the
 * GNU head take turns, each held 8 s with a 1 s fade and a 2 s empty gap
 * (the clone's vis.icon_* defaults). */
static void
draw_icon_cycle (BbClassicVis *self, cairo_t *cr,
                 int w, int h, double cx, double cy, double e, gboolean fast)
{
  if (!self->logo_tried) {
    self->logo_tried = TRUE;
    self->logo_mask = load_mask ("/net/launchpad/beatbox/icons/visualizer/tux-mono.svg");
  }
  if (!self->distro_tried) load_distro_logo (self);
  if (!self->gnu_tried) {
    self->gnu_tried = TRUE;
    self->gnu_mask = load_mask ("/net/launchpad/beatbox/icons/visualizer/gnu.svg");
  }

  IconKind list[5];
  int n = 0;
  if (self->logo_mask)   list[n++] = IK_TUX;
  if (self->distro_surf) list[n++] = IK_DISTRO;
  if (self->art_surf)    list[n++] = IK_ART;
  if (self->gnu_mask)    list[n++] = IK_GNU;
  if (n == 0) return;   /* nothing to show */

  double hold = 8, gap = 2, fade = 1;
  gap  = CLAMP (gap,  0.0, 120.0);
  fade = CLAMP (fade, 0.0, hold * 0.5);   /* fade can't exceed half the hold */

  double slot = hold + gap;                 /* one icon's full turn */
  double period = slot * n;                 /* whole cycle */
  double t = fmod (self->logo_clock, period);
  int idx = (int) (t / slot);               /* which icon's slot we're in */
  if (idx >= n) idx = n - 1;
  double in_slot = t - idx * slot;          /* 0..slot within this icon */

  /* Alpha within the slot: fade-in, hold, fade-out, then the empty gap. */
  double alpha;
  if (in_slot < fade)            alpha = fade > 0 ? in_slot / fade : 1.0;
  else if (in_slot < hold - fade) alpha = 1.0;
  else if (in_slot < hold)        alpha = fade > 0 ? (hold - in_slot) / fade : 1.0;
  else                            alpha = 0.0;   /* gap: nothing on screen */
  alpha = CLAMP (alpha, 0.0, 1.0);
  if (alpha <= 0.0) return;

  switch (list[idx]) {
  case IK_TUX:    draw_one_icon (cr, self->logo_mask,  TRUE,  cx, cy, w, h, e, alpha, fast); break;
  case IK_DISTRO: draw_one_icon (cr, self->distro_surf, FALSE, cx, cy, w, h, e, alpha, fast); break;
  case IK_ART:    draw_one_icon (cr, self->art_surf,    FALSE, cx, cy, w, h, e, alpha, fast); break;
  case IK_GNU:    draw_one_icon (cr, self->gnu_mask,    TRUE,  cx, cy, w, h, e, alpha, fast); break;
  }
}


/* One frame at w × h */
void
bb_classic_vis_draw (BbClassicVis *self, cairo_t *cr, int w, int h)
{

  /* Quality knob (read live): low = no antialiasing + nearest-neighbour image
   * scaling → cheaper on slow machines. High (default) = as before. */
  gboolean fast = FALSE;   /* vis.high_quality */

  /* Black background with a faint central radial gradient, tinted by the
   * theme (warm in amber, cool in ocean, etc.) to give depth. */
  const VisTheme *bt = &VIS_THEMES[self->theme % VIS_N_THEMES];
  cairo_pattern_t *bg = cairo_pattern_create_radial (
    w * 0.5, h * 0.5, 0, w * 0.5, h * 0.5, MAX (w, h) * 0.6);
  cairo_pattern_add_color_stop_rgb (bg, 0.0, bt->bg_r, bt->bg_g, bt->bg_b);
  cairo_pattern_add_color_stop_rgb (bg, 1.0, 0.0, 0.0, 0.0);
  cairo_set_source (cr, bg);
  cairo_paint (cr);
  cairo_pattern_destroy (bg);

  const double cx = w * 0.5, cy = h * 0.5;
  const double maxr = hypot (w, h) * 0.5;

  /* Icon position from config (center / corner / edge). Read live so
   * Preferences changes apply on the next frame. */
  double icx = cx, icy = cy;   /* vis.icon_pos: center */

  /* Global energy → overall brightness and "breathing". */
  double e = self->energy;

  /* Main layer according to the active style, with a CROSSFADE between
   * styles: during a transition we render the outgoing and incoming styles
   * cada uno en su grupo y los mezclamos por opacidad (disolvencia),
   * para que el cambio no sea brusco. */
  double te = smoothstep01 (self->transition);
  if (self->transition < 1.0) {
    cairo_push_group (cr);
    vis_draw_style (self, self->prev_style, cr, w, h, cx, cy, maxr, e);
    cairo_pop_group_to_source (cr);
    cairo_paint_with_alpha (cr, 1.0 - te);

    cairo_push_group (cr);
    vis_draw_style (self, self->style, cr, w, h, cx, cy, maxr, e);
    cairo_pop_group_to_source (cr);
    cairo_paint_with_alpha (cr, te);
  } else {
    vis_draw_style (self, self->style, cr, w, h, cx, cy, maxr, e);
  }

  /* Central core factor, also interpolated during the crossfade. */
  double cf = style_core_factor (self->style);
  if (self->transition < 1.0)
    cf = style_core_factor (self->prev_style) * (1.0 - te)
       + style_core_factor (self->style) * te;

  /* Bright central core that pulses with the energy (common to all
   * styles: it anchors the visual and leaves room for the logo). */
  double core_r = (30 + 120 * e) * (0.9 + 0.1 * sin (self->phase * 2.0));
  cairo_pattern_t *core = cairo_pattern_create_radial (cx, cy, 0, cx, cy, core_r);
  double cr0, cg0, cb0;
  vis_color (self, 0.55, 1.0, &cr0, &cg0, &cb0);
  cairo_pattern_add_color_stop_rgba (core, 0.0, 1.0, 0.97, 0.82, 0.95 * cf);
  cairo_pattern_add_color_stop_rgba (core, 0.35, 1.0, 0.85, 0.45, 0.8 * (0.5 + 0.5 * e) * cf);
  cairo_pattern_add_color_stop_rgba (core, 0.7, cr0, cg0, cb0, 0.4 * e * cf);
  cairo_pattern_add_color_stop_rgba (core, 1.0, cr0, cg0, cb0, 0.0);
  cairo_set_source (cr, core);
  cairo_arc (cr, cx, cy, core_r, 0, 2 * G_PI);
  cairo_fill (cr);
  cairo_pattern_destroy (core);

  /* Centre icon cycle: Tux / distro / album art / GNU rotate with fades and
   * empty gaps, all configured in Preferences › Window › Visualizer.
   * Position respects vis.icon_pos (center / corner / edge). */
  if (self->show_logos)
    draw_icon_cycle (self, cr, w, h, icx, icy, e, fast);
}

/* Cambia a un estilo ELEGIDO AL AZAR (distinto del actual) y a una
 * paleta al azar, arrancando la disolvencia suave. Sustituye al antiguo
 * sequential advance: so the order of styles is not predictable. */
/* A random index below n, in mask (when the mask leaves any), other than current if possible */
static int
pick_other (int n, guint mask, int current)
{
  int candidates[32];
  int count = 0;
  for (int i = 0; i < n && i < 32; i++)
    if ((mask & (1u << i)) && i != current)
      candidates[count++] = i;
  if (count == 0) {
    /* only the current one is chosen (or none): keep it if allowed, else any other */
    if (current >= 0 && (mask & (1u << current)))
      return current;
    for (int i = 0; i < n && i < 32; i++)
      if (i != current)
        candidates[count++] = i;
  }
  return count ? candidates[g_random_int_range (0, count)] : MAX (current, 0);
}

/* Cambia a un estilo ELEGIDO AL AZAR (distinto del actual, entre los que
 * Preferences deja) y a una paleta al azar, arrancando la disolvencia suave. */
static void
vis_switch_random (BbClassicVis *self)
{
  int next = pick_other (VIS_N_STYLES, self->style_mask, (int) self->style);
  if (next != (int) self->style) {
    self->prev_style = self->style;
    self->style = (VisStyle) next;
    self->transition = 0.0;      /* iniciar disolvencia hacia el nuevo estilo */
  }
  /* Palette also random, decoupled from the style, for lots of variety. */
  self->theme = pick_other (VIS_N_THEMES, self->theme_mask, self->theme);
}

/* One step of dt seconds with the spectrum's 10 bands (0..1; NULL = silence).
 * The effects were made for steps of 33 ms: every rate below is scaled to dt,
 * so the motion is the same at any frame rate (and `speed` times it). */
void
bb_classic_vis_tick (BbClassicVis *self, const float *bands, double dt)
{
  dt = CLAMP (dt, 0.001, 0.25);
  double steps = dt / 0.033;           /* how many of the original steps this one is */
  float mag[N_BANDS] = { 0 };
  if (bands)
    memcpy (mag, bands, sizeof mag);
  float attack = 1.0f - powf (1.0f - 0.6f, (float) steps);
  float decay = 1.0f - powf (1.0f - 0.12f, (float) steps);
  float sum = 0;
  for (int i = 0; i < N_BANDS; ++i) {
    float tgt = CLAMP (mag[i], 0.0f, 1.0f);
    /* Fast attack, slow decay for pleasant motion. */
    if (tgt > self->smooth[i]) self->smooth[i] += (tgt - self->smooth[i]) * attack;
    else                       self->smooth[i] += (tgt - self->smooth[i]) * decay;
    sum += self->smooth[i];
  }
  float e = CLAMP (sum / N_BANDS * 1.6f, 0.0f, 1.0f);
  self->energy += (e - self->energy) * (1.0f - powf (0.8f, (float) steps));

  /* Push a new column to the spectrogram history (it scrolls at its own pace). */
  self->spec_clock += dt * self->speed;
  while (self->spec_clock >= 0.033) {
    self->spec_clock -= 0.033;
    self->spec_head = (self->spec_head + 1) % SPEC_HIST_W;
    for (int i = 0; i < N_BANDS; ++i)
      self->spec_hist[self->spec_head][i] = self->smooth[i];
  }

  /* Advance the style crossfade toward 1. */
  if (self->transition < 1.0) {
    self->transition += dt / MAX (self->transition_s, 0.05);
    if (self->transition > 1.0) self->transition = 1.0;
  }

  /* The phase advances faster with more energy: the visual accelerates
   * with the music. */
  self->phase += (0.012 + self->energy * 0.05) * steps * self->speed;

  /* Reloj del fundido del logo (ver draw_icon_cycle). */
  self->logo_clock += dt;

  /* Automatic changes every interval_s seconds (unless auto_switch is off).
   * The change starts a smooth fade. */
  self->since_switch += dt;
  if (self->auto_switch && self->since_switch >= self->interval_s) {
    self->since_switch = 0.0;
    vis_switch_random (self);
  }
}

BbClassicVis *
bb_classic_vis_new (void)
{
  BbClassicVis *self = g_new0 (BbClassicVis, 1);
  self->transition = 1.0;          /* asentado: sin fundido al arrancar */
  self->switch_interval = 22.0;
  self->auto_switch = TRUE;
  self->speed = 1.0;
  self->transition_s = 1.3;
  self->interval_s = 22.0;
  self->show_logos = TRUE;
  self->style_mask = (1u << VIS_N_STYLES) - 1;
  self->theme_mask = (1u << VIS_N_THEMES) - 1;
  return self;
}

void
bb_classic_vis_free (BbClassicVis *self)
{
  if (!self) return;
  g_clear_pointer (&self->logo_mask, cairo_surface_destroy);
  g_clear_pointer (&self->distro_surf, cairo_surface_destroy);
  g_clear_pointer (&self->gnu_mask, cairo_surface_destroy);
  g_clear_pointer (&self->art_surf, cairo_surface_destroy);
  g_free (self);
}

/* A random other style and palette, with the fade (double click, "Next") */
void
bb_classic_vis_next (BbClassicVis *self)
{
  vis_switch_random (self);
  self->since_switch = 0.0;
}

int  bb_classic_vis_get_style (BbClassicVis *self) { return self->style; }
int  bb_classic_vis_get_theme (BbClassicVis *self) { return self->theme; }
int  bb_classic_vis_n_styles (void) { return VIS_N_STYLES; }
int  bb_classic_vis_n_themes (void) { return VIS_N_THEMES; }

void
bb_classic_vis_set_style (BbClassicVis *self, int style)
{
  if (style < 0 || style >= VIS_N_STYLES || style == (int) self->style) return;
  self->prev_style = self->style;
  self->style = (VisStyle) style;
  self->transition = 0.0;
  self->since_switch = 0.0;
}

void
bb_classic_vis_set_theme (BbClassicVis *self, int theme)
{
  if (theme >= 0 && theme < VIS_N_THEMES) self->theme = theme;
}

void
bb_classic_vis_set_auto (BbClassicVis *self, gboolean auto_switch)
{
  self->auto_switch = auto_switch;
  self->since_switch = 0.0;
}

/* The cover of the song playing, or NULL */
void
bb_classic_vis_set_artwork (BbClassicVis *self, GdkPixbuf *cover)
{
  g_clear_pointer (&self->art_surf, cairo_surface_destroy);
  if (cover) self->art_surf = surface_from_pixbuf (cover);
}

/* How the effects move: speed (1 = as made), seconds of the fade between two, seconds between
 * automatic changes, and whether the logos and the cover take turns in the middle */
void
bb_classic_vis_set_params (BbClassicVis *self, double speed, double transition_s,
                           double interval_s, gboolean show_logos)
{
  self->speed = CLAMP (speed, 0.05, 10.0);
  self->transition_s = CLAMP (transition_s, 0.05, 30.0);
  self->interval_s = CLAMP (interval_s, 1.0, 3600.0);
  self->show_logos = show_logos;
}

/* Which styles and palettes the automatic changes (and "Next") pick from: bit n is number n */
void
bb_classic_vis_set_masks (BbClassicVis *self, guint styles, guint themes)
{
  self->style_mask = styles;
  self->theme_mask = themes;
}

/* Starts on this style and palette, without a fade (-1: keeps the one there) */
void
bb_classic_vis_set_initial (BbClassicVis *self, int style, int theme)
{
  if (style >= 0 && style < VIS_N_STYLES) {
    self->style = (VisStyle) style;
    self->prev_style = (VisStyle) style;
    self->transition = 1.0;
  }
  if (theme >= 0 && theme < VIS_N_THEMES)
    self->theme = theme;
}

/* A random style and palette among the chosen ones (to start on) */
void
bb_classic_vis_randomize (BbClassicVis *self)
{
  bb_classic_vis_set_initial (self, pick_other (VIS_N_STYLES, self->style_mask, -1),
                              pick_other (VIS_N_THEMES, self->theme_mask, -1));
}
