/*
 * Writes a song's tags with TagLib's property interface (TagLib >= 2.0 C API),
 * which maps the same names onto ID3v2, Vorbis comments, MP4 atoms and so on.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

#include <glib.h>
#include <taglib/tag_c.h>

/* Sets each keys[i] to values[i] (an empty value removes the tag) and saves. */
gboolean
beatbox_write_tags (const char *path, char **keys, int n_keys, char **values, int n_values)
{
	if (path == NULL || n_keys != n_values)
		return FALSE;

	TagLib_File *file = taglib_file_new (path);
	if (file == NULL)
		return FALSE;

	gboolean ok = FALSE;
	/* only files where TagLib finds audio: it would put a tag on anything */
	const TagLib_AudioProperties *audio = taglib_file_is_valid (file) ? taglib_file_audioproperties (file) : NULL;
	if (audio != NULL && taglib_audioproperties_samplerate (audio) > 0) {
		for (int i = 0; i < n_keys; i++)
			taglib_property_set (file, keys[i], (values[i] != NULL && values[i][0] != '\0') ? values[i] : NULL);
		ok = taglib_file_save (file);
	}
	taglib_file_free (file);
	return ok;
}
