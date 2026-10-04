/*
 * Writes a picture into a file's tags with TagLib's C API (TagLib >= 2.0:
 * complex properties), for every format TagLib knows (MP3, FLAC, Ogg, MP4...).
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

#include <glib.h>
#include <taglib/tag_c.h>

/* The front cover of path becomes data (replacing the pictures it had). */
gboolean
beatbox_embed_cover (const char *path, const guint8 *data, gsize size, const char *mime_type)
{
	if (path == NULL || data == NULL || size == 0 || size > G_MAXUINT)
		return FALSE;

	TagLib_File *file = taglib_file_new (path);
	if (file == NULL)
		return FALSE;

	gboolean ok = FALSE;
	/* only files where TagLib finds audio: it would put a tag on anything */
	const TagLib_AudioProperties *audio = taglib_file_is_valid (file) ? taglib_file_audioproperties (file) : NULL;
	if (audio != NULL && taglib_audioproperties_samplerate (audio) > 0) {
		TAGLIB_COMPLEX_PROPERTY_PICTURE (picture, data, (unsigned int) size, "", mime_type, "Front Cover");
		ok = taglib_complex_property_set (file, "PICTURE", picture) && taglib_file_save (file);
	}
	taglib_file_free (file);
	return ok;
}
