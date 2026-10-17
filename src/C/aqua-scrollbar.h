#pragma once
#include <gtk/gtk.h>
G_BEGIN_DECLS

#define AQUA_TYPE_SCROLLBAR (aqua_scrollbar_get_type ())
G_DECLARE_FINAL_TYPE (AquaScrollbar, aqua_scrollbar, AQUA, SCROLLBAR, GtkWidget)

/* Barra de desplazamiento de Mac OS X Tiger (Aqua) dibujada con el arte de
 * aqua-art.c, en vertical u horizontal, con sus flechas juntas al pie. Comparte
 * el GtkAdjustment del GtkScrolledWindow, como gtk_scrollbar_new. */
GtkWidget *aqua_scrollbar_new (GtkAdjustment *adj, GtkOrientation orientation);

/* Envuelve un GtkScrolledWindow (ya con su child) en [fila [scroll | vbar] |
 * fila [hbar | esquina]], apaga sus barras nativas y devuelve la caja que va
 * donde iba el scrolled-window. La esquina solo aparece con las dos barras. */
GtkWidget *aqua_scrollbar_wrap (GtkWidget *scrolled_window);

G_END_DECLS
