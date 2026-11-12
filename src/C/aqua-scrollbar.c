/* aqua-scrollbar.c — barra de desplazamiento Aqua de Mac OS X Tiger, GTK4.
 *
 * Dibuja el arte de aqua-art.c en el «snapshot» del widget, con sus flechas ▲▼
 * juntas al pie (Tiger las pone en todas las barras): clic = un paso, mantener
 * = repetición. Clic en el canal = una página. La horizontal es la vertical
 * traspuesta. Comparte el GtkAdjustment del GtkScrolledWindow.
 *
 * El dibujo y la geometría no dependen de GTK (aqua-art.c, aqua-geometry.c);
 * aquí solo va la capa de GTK4: snapshot, medidas, gestos y cajas. */
#include "aqua-scrollbar.h"
#include "aqua-art.h"
#include "aqua-geometry.h"
#include <math.h>

#define ARROW_DELAY_MS  300   /* mantener una flecha: primera repetición */
#define ARROW_REPEAT_MS  50   /* … y luego cada tanto */

struct _AquaScrollbar {
  GtkWidget       parent_instance;
  GtkAdjustment  *adj;          /* ref propia; desconectar en dispose */
  gulong          h_value;      /* handler id "value-changed" */
  gulong          h_changed;    /* handler id "changed" */
  GtkOrientation  orientation;
  GtkGesture     *drag;
  GtkEventController *scroll;
  gboolean        dragging;
  double          grab_offset;  /* cursor - inicio del pomo, a lo largo del eje */
  AquaArtPress    press;        /* flecha mantenida pulsada */
  guint           repeat_id;    /* autorrepetición de la flecha */
  guint           vis_idle;     /* visibilidad pendiente (ver on_adj_changed) */
};

G_DEFINE_FINAL_TYPE (AquaScrollbar, aqua_scrollbar, GTK_TYPE_WIDGET)

/* ── geometría ligada al widget ───────────────────────────────────── */

/* Largo de la barra a lo largo de su eje. */
static double
bar_len (AquaScrollbar *self)
{
  return self->orientation == GTK_ORIENTATION_HORIZONTAL
           ? gtk_widget_get_width  (GTK_WIDGET (self))
           : gtk_widget_get_height (GTK_WIDGET (self));
}

/* Recorrido del pomo: entre el remate superior y las flechas. */
static double
travel_len (AquaScrollbar *self)
{
  return bar_len (self) - AQUA_ART_THUMB_TOP - AQUA_ART_THUMB_END;
}

/* Pomo en coordenadas del recorrido. FALSE si no hay nada que desplazar. */
static gboolean
pill_geometry (AquaScrollbar *self, double *out_pos, double *out_len)
{
  if (!self->adj) return FALSE;
  return aqua_slider_geometry (gtk_adjustment_get_value (self->adj),
                               gtk_adjustment_get_lower (self->adj),
                               gtk_adjustment_get_upper (self->adj),
                               gtk_adjustment_get_page_size (self->adj),
                               travel_len (self), out_pos, out_len);
}

/* Pomo en coordenadas de la barra, ajustado a píxeles de dispositivo: los
 * pomos de Tiger empiezan y acaban en píxel entero. */
static gboolean
thumb_rect (AquaScrollbar *self, double *y, double *len)
{
  double pos = 0, plen = 0;
  if (!pill_geometry (self, &pos, &plen)) return FALSE;
  int scale = gtk_widget_get_scale_factor (GTK_WIDGET (self));
  *y   = round ((AQUA_ART_THUMB_TOP + pos) * scale) / scale;
  *len = round (plen * scale) / scale;
  return TRUE;
}

/* Flecha bajo `at` (a lo largo del eje): el bloque son los últimos 32 px y la
 * frontera entre ▲ y ▼ es el centro del separador. */
static AquaArtPress
arrow_at (AquaScrollbar *self, double at)
{
  double y0 = bar_len (self) - AQUA_ART_ARROWS;
  if (at < y0) return AQUA_ART_PRESS_NONE;
  return at < y0 + 15.5 ? AQUA_ART_PRESS_UP : AQUA_ART_PRESS_DOWN;
}

/* ── dibujo y medidas ─────────────────────────────────────────────── */

static void
aqua_scrollbar_snapshot (GtkWidget *w, GtkSnapshot *snapshot)
{
  AquaScrollbar *self = AQUA_SCROLLBAR (w);
  int width = gtk_widget_get_width (w), height = gtk_widget_get_height (w);
  if (width <= 0 || height <= 0)
    return;

  graphene_rect_t bounds;
  graphene_rect_init (&bounds, 0, 0, width, height);
  cairo_t *cr = gtk_snapshot_append_cairo (snapshot, &bounds);
  cairo_save (cr);
  if (self->orientation == GTK_ORIENTATION_HORIZONTAL)
    aqua_art_transpose (cr);   /* desde aquí todo se dibuja en vertical */

  double ty = 0, tl = 0;
  gboolean has_thumb = thumb_rect (self, &ty, &tl);
  aqua_art_draw (cr, bar_len (self), ty, has_thumb ? tl : 0, self->press);
  cairo_restore (cr);
  cairo_destroy (cr);
}

/* A lo largo del eje caben el remate y las flechas; a lo ancho, los 15 px de
 * Tiger. */
static void
aqua_scrollbar_measure (GtkWidget *w, GtkOrientation orientation, int for_size,
                        int *min, int *nat, int *min_base, int *nat_base)
{
  (void) for_size;
  AquaScrollbar *self = AQUA_SCROLLBAR (w);
  gint size = orientation == self->orientation
                ? (gint) (AQUA_ART_THUMB_TOP + AQUA_ART_THUMB_END)
                : (gint) AQUA_ART_W;
  if (min) *min = size;
  if (nat) *nat = size;
  if (min_base) *min_base = -1;
  if (nat_base) *nat_base = -1;
}

/* ── señales del adjustment ───────────────────────────────────────── */

/* Hace falta scroll cuando el contenido es más grande que la página. */
static void
update_visibility (AquaScrollbar *self)
{
  gboolean need = gtk_adjustment_get_upper (self->adj)
                  - gtk_adjustment_get_lower (self->adj)
                  > gtk_adjustment_get_page_size (self->adj) + 0.5;
  gtk_widget_set_visible (GTK_WIDGET (self), need);
}

static gboolean
visibility_idle (gpointer ud)
{
  AquaScrollbar *self = AQUA_SCROLLBAR (ud);
  self->vis_idle = 0;
  update_visibility (self);
  return G_SOURCE_REMOVE;
}

static void
on_adj_changed (GtkAdjustment *adj, gpointer ud)
{
  (void) adj;
  AquaScrollbar *self = AQUA_SCROLLBAR (ud);
  /* El GtkScrolledWindow emite "changed" DENTRO de su size_allocate, y un
   * gtk_widget_set_visible ahí se pierde: el padre no vuelve a repartir y la
   * barra queda mostrada con 0 px de ancho. Se decide fuera, en un idle. */
  if (!self->vis_idle)
    self->vis_idle = g_idle_add (visibility_idle, self);
  gtk_widget_queue_draw (GTK_WIDGET (self));
}

/* ── entrada: flechas, drag, click-en-canal, rueda ────────────────── */

static void
arrow_step (AquaScrollbar *self)
{
  if (!self->adj) return;
  double step = gtk_adjustment_get_step_increment (self->adj);
  if (step <= 0) step = 40.0;
  double dir = self->press == AQUA_ART_PRESS_UP ? -1.0 : 1.0;
  /* gtk_adjustment_set_value ya acota a [lower, upper - page]. */
  gtk_adjustment_set_value (self->adj, gtk_adjustment_get_value (self->adj) + dir * step);
}

static gboolean
arrow_repeat_tick (gpointer ud)
{
  arrow_step (AQUA_SCROLLBAR (ud));
  return G_SOURCE_CONTINUE;
}

static gboolean
arrow_repeat_start (gpointer ud)
{
  AquaScrollbar *self = AQUA_SCROLLBAR (ud);
  arrow_step (self);
  self->repeat_id = g_timeout_add (ARROW_REPEAT_MS, arrow_repeat_tick, self);
  return G_SOURCE_REMOVE;
}

static void
arrow_release (AquaScrollbar *self)
{
  g_clear_handle_id (&self->repeat_id, g_source_remove);
  if (self->press != AQUA_ART_PRESS_NONE) {
    self->press = AQUA_ART_PRESS_NONE;
    gtk_widget_queue_draw (GTK_WIDGET (self));
  }
}

/* Inversa EXACTA de pill_geometry para seguir el cursor sin jitter.
 * `pill_pos` va en coordenadas del recorrido. */
static void
set_value_from_pill_pos (AquaScrollbar *self, double pill_pos)
{
  double ppos = 0, plen = 0;
  if (!pill_geometry (self, &ppos, &plen)) return;

  double lower = gtk_adjustment_get_lower (self->adj);
  double upper = gtk_adjustment_get_upper (self->adj);
  double page  = gtk_adjustment_get_page_size (self->adj);
  double range = upper - lower - page;
  double travel = travel_len (self) - plen;
  if (range <= 0 || travel <= 0) return;

  gtk_adjustment_set_value (self->adj, lower + (pill_pos / travel) * range);
}

static void
on_drag_begin (GtkGestureDrag *g, double sx, double sy, gpointer ud)
{
  AquaScrollbar *self = AQUA_SCROLLBAR (ud);
  self->dragging = FALSE;
  if (!self->adj) return;
  double cursor = (self->orientation == GTK_ORIENTATION_HORIZONTAL) ? sx : sy;

  AquaArtPress arrow = arrow_at (self, cursor);
  if (arrow != AQUA_ART_PRESS_NONE) {
    arrow_release (self);
    self->press = arrow;
    arrow_step (self);
    self->repeat_id = g_timeout_add (ARROW_DELAY_MS, arrow_repeat_start, self);
    gtk_widget_queue_draw (GTK_WIDGET (self));
    return;
  }

  double ppos = 0, plen = 0;
  if (!pill_geometry (self, &ppos, &plen)) return;
  ppos += AQUA_ART_THUMB_TOP;
  if (cursor >= ppos && cursor <= ppos + plen) {
    self->dragging = TRUE;
    self->grab_offset = cursor - ppos;
  } else {
    double page = gtk_adjustment_get_page_size (self->adj);
    double cur  = gtk_adjustment_get_value (self->adj);
    gtk_adjustment_set_value (self->adj, cur + (cursor < ppos ? -page : page));
    gtk_gesture_set_state (GTK_GESTURE (g), GTK_EVENT_SEQUENCE_DENIED);
  }
}

static void
on_drag_update (GtkGestureDrag *g, double ox, double oy, gpointer ud)
{
  AquaScrollbar *self = AQUA_SCROLLBAR (ud);
  if (!self->dragging) return;
  double sx = 0, sy = 0;
  gtk_gesture_drag_get_start_point (g, &sx, &sy);
  double cursor = (self->orientation == GTK_ORIENTATION_HORIZONTAL)
                    ? (sx + ox) : (sy + oy);
  set_value_from_pill_pos (self, cursor - self->grab_offset - AQUA_ART_THUMB_TOP);
}

static void
on_drag_end (GtkGestureDrag *g, double ox, double oy, gpointer ud)
{
  (void) g; (void) ox; (void) oy;
  AquaScrollbar *self = AQUA_SCROLLBAR (ud);
  self->dragging = FALSE;
  arrow_release (self);
}

static gboolean
on_scroll (GtkEventControllerScroll *c, double dx, double dy, gpointer ud)
{
  AquaScrollbar *self = AQUA_SCROLLBAR (ud);
  (void) c;
  if (!self->adj) return GDK_EVENT_PROPAGATE;
  double step = gtk_adjustment_get_step_increment (self->adj);
  if (step <= 0) step = 40.0;
  double delta = (self->orientation == GTK_ORIENTATION_HORIZONTAL) ? dx : dy;
  double cur = gtk_adjustment_get_value (self->adj);
  gtk_adjustment_set_value (self->adj, cur + delta * step);
  return GDK_EVENT_STOP;
}

/* ── ciclo de vida ────────────────────────────────────────────────── */

static void
aqua_scrollbar_dispose (GObject *o)
{
  AquaScrollbar *self = AQUA_SCROLLBAR (o);
  g_clear_handle_id (&self->repeat_id, g_source_remove);
  g_clear_handle_id (&self->vis_idle, g_source_remove);
  /* Desconectar los handlers del adjustment ANTES de soltar la ref: el adj lo
   * posee el GtkScrolledWindow y puede sobrevivir al widget. */
  if (self->adj) {
    if (self->h_value)   g_clear_signal_handler (&self->h_value,   self->adj);
    if (self->h_changed) g_clear_signal_handler (&self->h_changed, self->adj);
  }
  g_clear_object (&self->adj);
  /* drag y scroll los posee el widget (gtk_widget_add_controller): no se sueltan aquí. */
  G_OBJECT_CLASS (aqua_scrollbar_parent_class)->dispose (o);
}

static void
aqua_scrollbar_class_init (AquaScrollbarClass *k)
{
  G_OBJECT_CLASS (k)->dispose = aqua_scrollbar_dispose;
  GtkWidgetClass *wc = GTK_WIDGET_CLASS (k);
  wc->snapshot = aqua_scrollbar_snapshot;
  wc->measure = aqua_scrollbar_measure;
}

static void
aqua_scrollbar_init (AquaScrollbar *self)
{
  self->orientation = GTK_ORIENTATION_VERTICAL;
  gtk_widget_add_css_class (GTK_WIDGET (self), "aqua-scrollbar");

  /* GTK4: los gestos son controladores añadidos al widget; no hace falta una
   * ventana propia ni máscaras de eventos. */
  self->drag = gtk_gesture_drag_new ();
  gtk_widget_add_controller (GTK_WIDGET (self), GTK_EVENT_CONTROLLER (self->drag));
  g_signal_connect (self->drag, "drag-begin",  G_CALLBACK (on_drag_begin),  self);
  g_signal_connect (self->drag, "drag-update", G_CALLBACK (on_drag_update), self);
  g_signal_connect (self->drag, "drag-end",    G_CALLBACK (on_drag_end),    self);
}

/* ── constructor y envoltorio ─────────────────────────────────────── */

GtkWidget *
aqua_scrollbar_new (GtkAdjustment *adj, GtkOrientation orientation)
{
  AquaScrollbar *self = g_object_new (AQUA_TYPE_SCROLLBAR, NULL);
  self->orientation = orientation;
  /* Empieza oculta: su visibilidad la decide el adjustment (update_visibility). */
  gtk_widget_set_visible (GTK_WIDGET (self), FALSE);
  if (adj) {
    self->adj = g_object_ref (adj);
    self->h_value =
        g_signal_connect (adj, "value-changed", G_CALLBACK (on_adj_changed), self);
    self->h_changed =
        g_signal_connect (adj, "changed", G_CALLBACK (on_adj_changed), self);
    update_visibility (self);
  }
  gtk_widget_add_css_class (GTK_WIDGET (self),
      orientation == GTK_ORIENTATION_HORIZONTAL ? "aqua-hbar" : "aqua-vbar");

  GtkEventControllerScrollFlags flags =
      (orientation == GTK_ORIENTATION_HORIZONTAL)
          ? GTK_EVENT_CONTROLLER_SCROLL_HORIZONTAL
          : GTK_EVENT_CONTROLLER_SCROLL_VERTICAL;
  self->scroll = gtk_event_controller_scroll_new (flags);
  gtk_widget_add_controller (GTK_WIDGET (self), self->scroll);
  g_signal_connect (self->scroll, "scroll", G_CALLBACK (on_scroll), self);
  return GTK_WIDGET (self);
}

/* La esquina donde se cruzan las dos barras solo existe con ambas visibles. */
static void
sync_corner (GtkWidget *bar, GParamSpec *p, gpointer corner)
{
  (void) bar; (void) p;
  GtkWidget *vbar = g_object_get_data (G_OBJECT (corner), "aqua-vbar");
  GtkWidget *hbar = g_object_get_data (G_OBJECT (corner), "aqua-hbar");
  gtk_widget_set_visible (GTK_WIDGET (corner),
                          gtk_widget_get_visible (vbar) && gtk_widget_get_visible (hbar));
}

GtkWidget *
aqua_scrollbar_wrap (GtkWidget *sw)
{
  g_return_val_if_fail (GTK_IS_SCROLLED_WINDOW (sw), sw);

  GtkScrolledWindow *scroll = GTK_SCROLLED_WINDOW (sw);

  /* Lo que decide el sitio del scrolled-window en su padre (expansión, márgenes,
   * alineación) pasa al envoltorio; dentro, el scrolled-window queda sin ellos. */
  gboolean hexpand = gtk_widget_get_hexpand (sw), vexpand = gtk_widget_get_vexpand (sw);
  GtkAlign halign = gtk_widget_get_halign (sw), valign = gtk_widget_get_valign (sw);
  int margins[4] = { gtk_widget_get_margin_top (sw), gtk_widget_get_margin_bottom (sw),
                     gtk_widget_get_margin_start (sw), gtk_widget_get_margin_end (sw) };
  gtk_widget_set_margin_top (sw, 0);
  gtk_widget_set_margin_bottom (sw, 0);
  gtk_widget_set_margin_start (sw, 0);
  gtk_widget_set_margin_end (sw, 0);

  /* Apagar las barras nativas que tenían los ejes (EXTERNAL); un eje que ya estaba
   * en NEVER se queda así: sin barra, con el mismo tamaño natural, y el desplazamiento
   * sigue funcionando. Las nuestras las dibujan los widgets cairo. */
  GtkPolicyType hpolicy, vpolicy;
  gtk_scrolled_window_get_policy (scroll, &hpolicy, &vpolicy);
  gtk_scrolled_window_set_policy (scroll,
      hpolicy == GTK_POLICY_NEVER ? GTK_POLICY_NEVER : GTK_POLICY_EXTERNAL,
      vpolicy == GTK_POLICY_NEVER ? GTK_POLICY_NEVER : GTK_POLICY_EXTERNAL);

  /* [fila [scroll | vbar] | fila [hbar | esquina]]: como en Tiger, la horizontal
   * acaba donde empieza la vertical y sus flechas quedan junto a la esquina. */
  GtkWidget *row = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_hexpand (sw, TRUE);
  gtk_widget_set_vexpand (sw, TRUE);
  gtk_box_append (GTK_BOX (row), sw);

  GtkWidget *vbar = aqua_scrollbar_new (
      gtk_scrolled_window_get_vadjustment (scroll), GTK_ORIENTATION_VERTICAL);
  gtk_widget_set_vexpand (vbar, TRUE);
  gtk_box_append (GTK_BOX (row), vbar);

  GtkWidget *hrow = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0);
  GtkWidget *hbar = aqua_scrollbar_new (
      gtk_scrolled_window_get_hadjustment (scroll), GTK_ORIENTATION_HORIZONTAL);
  gtk_widget_set_hexpand (hbar, TRUE);
  gtk_box_append (GTK_BOX (hrow), hbar);

  /* La esquina se muestra u oculta en sync_corner, justo al crearla. */
  GtkWidget *corner = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_add_css_class (corner, "aqua-corner");
  gtk_widget_set_size_request (corner, (int) AQUA_ART_W, (int) AQUA_ART_W);
  gtk_box_append (GTK_BOX (hrow), corner);
  g_object_set_data (G_OBJECT (corner), "aqua-vbar", vbar);
  g_object_set_data (G_OBJECT (corner), "aqua-hbar", hbar);
  g_signal_connect_object (vbar, "notify::visible", G_CALLBACK (sync_corner), corner, 0);
  g_signal_connect_object (hbar, "notify::visible", G_CALLBACK (sync_corner), corner, 0);
  sync_corner (NULL, NULL, corner);

  GtkWidget *col = gtk_box_new (GTK_ORIENTATION_VERTICAL, 0);
  gtk_widget_set_hexpand (col, hexpand);
  gtk_widget_set_vexpand (col, vexpand);
  gtk_widget_set_halign (col, halign);
  gtk_widget_set_valign (col, valign);
  gtk_widget_set_margin_top (col, margins[0]);
  gtk_widget_set_margin_bottom (col, margins[1]);
  gtk_widget_set_margin_start (col, margins[2]);
  gtk_widget_set_margin_end (col, margins[3]);
  gtk_widget_set_hexpand (row, TRUE);
  gtk_widget_set_vexpand (row, TRUE);
  gtk_box_append (GTK_BOX (col), row);
  gtk_box_append (GTK_BOX (col), hrow);
  gtk_widget_set_visible (sw, TRUE);
  gtk_widget_set_visible (row, TRUE);
  gtk_widget_set_visible (hrow, TRUE);
  gtk_widget_set_visible (col, TRUE);
  /* Devuelve una referencia propia: quien lo recibe (Vala) la suelta cuando
   * ya la tiene el contenedor. */
  return g_object_ref_sink (col);
}
