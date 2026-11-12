/* offscreen-gl.c — lo que projectM necesita del proceso para el visualizador
 * (src/Widgets/Visualizer.vala): un contexto OpenGL fuera de pantalla y números
 * con punto decimal.
 *
 * projectM 4.1 dibuja siempre en el framebuffer 0 e ignora el FBO que esté
 * ligado, así que dentro de un GtkGLArea su imagen se pierde. Aquí el
 * framebuffer 0 es un pbuffer EGL del tamaño de la vista: projectM dibuja en
 * él, se lee con glReadPixels y la vista lo pinta con cairo. GTK no usa GL y
 * projectM no toca ningún otro contexto. */
#define _GNU_SOURCE /* newlocale, uselocale */
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <glib.h>
#include <locale.h>

typedef struct {
	EGLDisplay display;
	EGLConfig config;
	EGLContext context;
	EGLSurface surface;
	int width, height;
} BbOffscreenGL;

static EGLDisplay open_display (void)
{
	/* sin ventana ni servidor gráfico; si el driver no lo tiene (no Mesa), el de siempre */
	EGLDisplay display = eglGetPlatformDisplay (EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
	if (display != EGL_NO_DISPLAY && eglInitialize (display, NULL, NULL))
		return display;
	display = eglGetDisplay (EGL_DEFAULT_DISPLAY);
	if (display != EGL_NO_DISPLAY && eglInitialize (display, NULL, NULL))
		return display;
	return EGL_NO_DISPLAY;
}

/* El contexto, aún sin superficie: NULL si no hay OpenGL 3.3 */
BbOffscreenGL *bb_offscreen_gl_new (void)
{
	BbOffscreenGL *gl = g_new0 (BbOffscreenGL, 1);
	gl->display = open_display ();
	EGLint config_attribs[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
	                            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE };
	EGLint context_attribs[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 3,
	                             EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE };
	EGLint n = 0;
	if (gl->display == EGL_NO_DISPLAY
	    || !eglChooseConfig (gl->display, config_attribs, &gl->config, 1, &n) || n < 1
	    || !eglBindAPI (EGL_OPENGL_API)
	    || (gl->context = eglCreateContext (gl->display, gl->config, EGL_NO_CONTEXT, context_attribs)) == EGL_NO_CONTEXT) {
		g_warning ("Visualizer: no OpenGL 3.3 off screen (EGL error 0x%x)", eglGetError ());
		g_free (gl);
		return NULL;
	}
	gl->surface = EGL_NO_SURFACE;
	return gl;
}

/* Un pbuffer nuevo de width × height (un pbuffer no cambia de tamaño), ya activo */
gboolean bb_offscreen_gl_resize (BbOffscreenGL *gl, int width, int height)
{
	EGLint attribs[] = { EGL_WIDTH, width, EGL_HEIGHT, height, EGL_NONE };
	EGLSurface surface = eglCreatePbufferSurface (gl->display, gl->config, attribs);
	if (surface == EGL_NO_SURFACE || !eglMakeCurrent (gl->display, surface, surface, gl->context)) {
		g_warning ("Visualizer: no %d×%d pbuffer (EGL error 0x%x)", width, height, eglGetError ());
		if (surface != EGL_NO_SURFACE)
			eglDestroySurface (gl->display, surface);
		return FALSE;
	}
	if (gl->surface != EGL_NO_SURFACE)
		eglDestroySurface (gl->display, gl->surface);
	gl->surface = surface;
	gl->width = width;
	gl->height = height;
	return TRUE;
}

void bb_offscreen_gl_make_current (BbOffscreenGL *gl)
{
	eglMakeCurrent (gl->display, gl->surface, gl->surface, gl->context);
}

/* El cuadro dibujado, en BGRA (el orden de cairo en little endian), de abajo arriba:
 * pixels tiene sitio para width × height × 4 bytes */
void bb_offscreen_gl_read (BbOffscreenGL *gl, guint8 *pixels)
{
	glBindFramebuffer (GL_READ_FRAMEBUFFER, 0);
	glPixelStorei (GL_PACK_ALIGNMENT, 4);
	glReadPixels (0, 0, gl->width, gl->height, GL_BGRA, GL_UNSIGNED_BYTE, pixels);
}

void bb_offscreen_gl_free (BbOffscreenGL *gl)
{
	if (gl == NULL)
		return;
	eglMakeCurrent (gl->display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	if (gl->surface != EGL_NO_SURFACE)
		eglDestroySurface (gl->display, gl->surface);
	eglDestroyContext (gl->display, gl->context);
	g_free (gl);
}

/* projectM 4.1 lee y escribe sus números con las funciones de C (strtod, printf): con la
 * coma decimal del sistema su escena queda negra. Mientras trabaja, este hilo usa números
 * "C"; el resto (la interfaz: "4,1 MB") sigue con los del sistema. Devuelve el locale que
 * había, para bb_c_numbers_end. */
void *bb_c_numbers_begin (void)
{
	static locale_t c_numbers = (locale_t) 0;
	if (c_numbers == (locale_t) 0)
		c_numbers = newlocale (LC_NUMERIC_MASK, "C", duplocale (LC_GLOBAL_LOCALE));
	return uselocale (c_numbers);
}

void bb_c_numbers_end (void *previous)
{
	uselocale ((locale_t) previous);
}
