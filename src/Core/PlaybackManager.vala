/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 * 
 * The BeatBox project hereby grant permission for non-gpl compatible GStreamer
 * plugins to be used and distributed together with GStreamer and BeatBox. This
 * permission is above and beyond the permissions granted by the GPL license
 * BeatBox is covered by.
 *
 * Manages all playback aspects including the currently playing list, shuffle mode, repeat mode,
 * current media info, queue, history, and interaction with gstreamer.
*/
using Gee;

public class BeatBox.PlaybackManager : GLib.Object, BeatBox.PlaybackInterface {
	public const int PREVIEW_MEDIA_ID = -2;
	
	Streamer player;
	
	public bool media_active { get { return current_media != null; } }
	
	bool _playing_queued_song;
	PlaybackInterface.RepeatMode repeat_mode;
	PlaybackInterface.ShuffleMode shuffle_mode;
	public int next_gapless_id;
	
	public int _played_index;//if user press back, this goes back 1 until it hits 0. as new medias play, this goes with it
	public Media current_media { get; protected set; }
	
	private LinkedList<Media> _queue; // rowid, Media of queue
	private LinkedList<Media> _history; // Media of already played
	
	HashMap<int, Media> playback_reference_list; // used to unshuffle/shuffle, but always kept in order
	HashMap<int, Media> playback_used_list; // could be shuffled, could be *copy* (not reference) of reference list.
	
	private bool _playing;
	public bool playing {
		get { return _playing; }
	}
	
	private bool queriedlastfm; // whether or not we have queried last fm for the current media info
	private bool media_considered_played; // whether or not we have updated last played and added to already played list
	private bool added_to_play_count; // the listener got through (most of) the media, so skipping it later doesn't count as a skip
	private bool play_counted;        // whether or not this play was already added to the play count
	private bool scrobbled_track;
	
	public PlaybackManager() {
		this.player = new Streamer();
		
		playback_reference_list = new HashMap<int, Media>();
		playback_used_list = new HashMap<int, Media>();
		_queue = new LinkedList<Media>();
		// saved as it changes, so it survives a crash too (restored in load_and_play_last_playing)
		queue_changed.connect(() => {
			string[] ids = {};
			foreach(var m in _queue)
				ids += m.rowid.to_string();
			App.settings.saved_state.queue = ids;
		});
		_history = new LinkedList<Media>();
		
		_played_index = 0;
		
		repeat_mode = (PlaybackInterface.RepeatMode)App.settings.main.repeat_mode;
		shuffle_mode = (PlaybackInterface.ShuffleMode)App.settings.main.shuffle_mode;
		
		// Keeps the signal going from Streamer
		player.end_of_stream.connect(internal_end_of_stream);
		player.buffer_percent_update.connect( (percent) => { buffer_percent_update(percent); } );
		player.current_position_update.connect(internal_current_position_update);
		player.video_enabled.connect( () => { video_enabled(); } );
		player.spectrum_update.connect( (magnitudes) => { spectrum_update(magnitudes); } );
	}
	
	/** The song BeatBox was closed on: nothing is loaded at startup, and Play alone goes on with it */
	Media? to_resume = null;
	
	public void load_and_play_last_playing() {
		Media? restore_song = App.library.media_from_id(App.settings.main.last_media_playing);
		if(restore_song != null && !media_active) // else a file opened at startup is already on
			to_resume = restore_song;
		
		// The queue as it was when BeatBox was closed
		var queued = new LinkedList<Media>();
		foreach(var id in App.settings.saved_state.queue) {
			var m = App.library.media_from_id(int.parse(id));
			if(m != null)
				queued.add(m);
		}
		if(queued.size > 0)
			queue_medias(queued);
		
		// Set the initial view
		App.window.setup_playback();
		
		// TODO: Fix video. Or don't support it?
		//set_video_enabled(true);
	}
	
	/**************** Basic playback **********************/
	public void play() {
		if(!media_active && to_resume != null) {
			resume_last();
			return;
		}
		if(!App.playback.media_active) {
			debug("No media is currently playing. Starting from the top\n");
			start_playback_requested();
		}
		else {
			_playing = true;
			player.play();
			
			playback_played();
		}
	}
	
	public void pause() {
		_playing = false;
		player.pause();
		
		playback_paused();
	}
	
	// TODO: Should the position be cached?
	public int64 get_position() {
		return player.getPosition();
	}
	
	public void set_position(int64 pos) {
		player.setPosition(pos);
	}
	
	public int64 get_duration() {
		return player.getDuration();
	}
	
	public double get_volume() {
		return player.getVolume();
	}
	
	public void set_volume(double val) {
		player.setVolume(val);
	}
	
	public void want_spectrum(bool wanted) {
		player.want_spectrum(wanted);
	}
	
	/**************** Video ******************************/
	public void set_video_enabled(bool val) {
		player.setVideoEnabled(val);
	}
	
	/**************** Queue Stuff **************************/
	public bool queue_empty() {
		return _queue.is_empty;
	}
	
	public void clear_queue() {
		_queue.clear();
		queue_changed();
	}
	
	public void queue_medias(Collection<Media> medias) {
		foreach(var m in medias) {
			_queue.offer(m);
		}
		
		queue_changed();
	}
	
	public void insert_in_queue(Collection<Media> medias, int index) {
		ListUtils.move_to(_queue, medias, index);
		queue_changed();
	}
	
	public void move_in_queue(Media m, int delta) {
		int i = _queue.index_of(m);
		if(i < 0)
			return;
		_queue.remove_at(i);
		_queue.insert((i + delta).clamp(0, _queue.size), m);
		queue_changed();
	}
	
	public void unqueue_media(Media m) {
		_queue.remove(m);
		queue_changed();
	}
	
	public Media peek_queue() {
		return _queue.peek();
	}
	
	public Media poll_queue() {
		var rv = _queue.poll();
		queue_changed();
		
		return rv;
	}
	
	public LinkedList<Media> queue() {
		return _queue;
	}
	
	/************ Already Played Stuff **************/
	public bool history_empty() {
		return _history.size == 0;
	}
	
	public void reset_history() {
		_history.clear();
		history_changed();
	}
	
	public void add_to_history(Media m) {
		if(!_history.contains(m))
			_history.add(m);
		
		history_changed();
	}
	
	public LinkedList<Media> history() {
		return _history;
	}
	
	/************ Current medialist stuff ***************/
	public int current_index { get; protected set; }
	
	public bool playing_queued_song() {
		return _playing_queued_song;
	}
	
	public Media media_from_playback_list_index(int index_in_current) {
		return playback_used_list.get(index_in_current);
	}
	
	public Collection<Media> current_medias() {
		return playback_used_list.values;
	}
	
	
	public void clear_playback_list() {
		current_cleared();
		playback_used_list.clear();
		playback_reference_list.clear();
	}
	
	// sets playback_reference_list. Then, if shuffle is turned on, shuffles list and saves
	// the shuffled list to playback_used_list
	// sets current index to index of m if m is not null. otherwise, sets
	// index to idnex of currently playing song
	//
	// TODO: Make this more efficient by shuffling used_list on initial populate and setting current_index there too
	public void set_playback_list(LinkedList<Media> list, Media? media) {
		clear_playback_list();
		
		current_index = 0;
		
		foreach(Media m in list) {
			playback_reference_list.set((int)playback_reference_list.size, m);
			playback_used_list.set((int)playback_used_list.size, m);
		}
		
		if(shuffle_mode == ShuffleMode.ALL) {
			shuffle_used_list();
		}
		
		// Set current index
		for(int i = 0; i < playback_used_list.size; ++i) {
			Media m = playback_used_list.get(i);
			
			if(media == m || (media == null && current_media == m)) {
				current_index = i;
				break;
			}
		}
	}
	
	
	/************** Shuffle ***********************/
	private void swap (int a, int b) {
		Media temp = playback_used_list.get(a);
		playback_used_list.set(a, playback_used_list.get(b));
		playback_used_list.set(b, temp);
	}
	
	private void shuffle_used_list() {
		int m = playback_used_list.size;
		int i;
		
		// While there are remain elements to shuffle, pick
		// a random remaining element and swap it with the current
		while (m > 0) {
			i = (int)(GLib.Random.next_int() % m--);
			swap(m, i);
		}
		
		find_new_current_index();
	}
	
	private void unshuffle_used_list() {
		playback_used_list.clear();
		
		for(int i = 0; i < playback_reference_list.size; ++i) {
			playback_used_list.set(i, playback_reference_list.get(i));
		}
		
		find_new_current_index();
	}
	
	void find_new_current_index() {
		if(current_media == null) {
			return;
		}
		
		for(int i = 0; i < playback_used_list.size; ++i) {
			if(playback_used_list.get(i) == current_media) {
				current_index = i;
				return;
			}
		}
	}
	
	public void set_shuffle_mode(PlaybackInterface.ShuffleMode mode) {
		if(mode == shuffle_mode)
			return;
		
		shuffle_mode = mode;
		App.settings.main.shuffle_mode = mode;
		
		if(mode == PlaybackInterface.ShuffleMode.ALL) {
			shuffle_used_list();
		}
		else {
			unshuffle_used_list();
		}
	}
	
	public PlaybackInterface.ShuffleMode get_shuffle_mode() {
		return shuffle_mode;
	}
	
	public bool is_shuffled { get { return shuffle_mode == ShuffleMode.ALL; } }
	
	/****************** Repeat *********************/
	public void set_repeat_mode(PlaybackInterface.RepeatMode mode) {
		repeat_mode = mode;
		App.settings.main.repeat_mode = repeat_mode;
	}
	
	public PlaybackInterface.RepeatMode get_repeat_mode() {
		return repeat_mode;
	}
	
	bool repeats_group() {
		return repeat_mode == RepeatMode.ARTIST || repeat_mode == RepeatMode.ALBUM;
	}
	
	// The first (step -1) or last (1) song in a row of the artist or album playing
	int group_edge(int step) {
		return ListUtils.run_edge(current_index, playback_used_list.size, step, (a, b) => {
			Media x = playback_used_list.get(a), y = playback_used_list.get(b);
			return repeat_mode == RepeatMode.ARTIST ? x.artist == y.artist : x.album == y.album;
		});
	}
	
	// Moves the current index to the next song and returns that media
	// Only plays if play is true
	public Media? getNext(bool play) {
		Media? rv = step_next(play);
		// songs marked "skip when shuffling" (Options tab) are passed by, one round at most
		for(int i = 0; rv != null && skipped_in_shuffle(rv) && i < playback_used_list.size; i++)
			rv = step_next(play);
		
		if(play && rv != null) // none when the song playing isn't in the list
			play_media(rv, false);
		
		return rv;
	}
	
	bool skipped_in_shuffle(Media m) {
		// and songs with no file (last.fm suggestions in Similar) can't be played in a row
		return (m.skip_shuffle && shuffle_mode == ShuffleMode.ALL && !_playing_queued_song) || m.uri == "";
	}
	
	Media? step_next(bool play) {
		Media rv = null;
		
		// next check if user has queued medias
		if(!queue_empty()) {
			rv = poll_queue();
			_playing_queued_song = true;
		}
		else {
			_playing_queued_song = false;
			
			if(current_media == null) {
				current_index = 0;
				rv = playback_used_list.get(0);
			}
			else if(repeat_mode == RepeatMode.MEDIA) {
				rv = playback_used_list.get(current_index);
			}
			else if(current_index == (playback_used_list.size - 1)) {
				if(repeats_group())
					current_index = group_edge(-1); // the list ends with this artist or album: back to its start
				else if(repeat_mode == RepeatMode.ALL)
					current_index = 0;
				else {
					if(play)
						stop_playback();
					return null;
				}
				
				rv = playback_used_list.get(0);
			}
			else if(current_index >= 0 && current_index < (playback_used_list.size - 1)){
				if(repeats_group() && group_edge(1) == current_index)
					current_index = group_edge(-1); // the artist or album ends here: back to its start
				else
					++current_index;
				
				rv = playback_used_list.get(current_index);
			}
		}
		
		return rv;
	}
	
	// Moves the current index to the previous song and returns that media
	// Only plays if play is true
	public Media? getPrevious(bool play) {
		Media? rv = step_previous();
		for(int i = 0; rv != null && skipped_in_shuffle(rv) && i < playback_used_list.size; i++)
			rv = step_previous();
		
		if(play && rv != null)
			play_media(rv, false);
		
		return rv;
	}
	
	Media? step_previous() {
		Media rv = null;
		
		_playing_queued_song = false;
		
		if(current_media == null) {
			current_index = (int)playback_used_list.size - 1;
			rv = playback_used_list.get(current_index);
		}
		else if(repeat_mode == RepeatMode.MEDIA) {
			rv = playback_used_list.get(current_index);
		}
		else if(current_index == (0)) {// consider repeat options
			if(repeats_group())
				current_index = group_edge(1); // the list starts with this artist or album: on to its end
			else if(repeat_mode == RepeatMode.ALL)
				current_index = (int)playback_used_list.size - 1;
			else {
				stop_playback();
				return null;
			}
			
			rv = playback_used_list.get(current_index);
		}
		else if(current_index > 0 && current_index < playback_used_list.size){
			if(repeats_group() && group_edge(-1) == current_index)
				current_index = group_edge(1); // the artist or album starts here: on to its end
			else
				--current_index;
			
			rv = playback_used_list.get(current_index);
		}
		
		return rv;
	}
	
	public void request_previous() {
		// TODO: This should be abstracted out on what to do on previous request
		if(get_position() < 5000000000 || (media_active && current_media is Station)) {
			Media prev = getPrevious(true);

			/* test to stop playback/reached end */
			if(prev == null) {
				stop_playback();
			}
		}
		else {
			set_position(0);
		}
	}
	
	public void request_next() {
		// if not 90% done, skip it
		if(!added_to_play_count) {
			current_media.skip_count++;
		}

		Media next = getNext(true);
		
		/* test to stop playback/reached end */
		if(next == null) {
			stop_playback();
		}
	}
	
	void internal_end_of_stream() {
		// Only call request next if we are not doing gapless. If we are,
		// then the next media will be played within player
		if(!player.doing_gapless) {
			// a song already taken from the list for a crossfade that couldn't be done
			var next = player.take_next_after_eos();
			if(next != null)
				play_media(next, false);
			else
				request_next();
		}
		
		end_of_stream();
	}
	
	/***************** Playing media **********************
	 * There is a lot of stuff here that shouldn't be and belongs
	 * somewhere else.
	 * 
	 * playMedia allows components to play a temporary song OR permanent song
	 * with ease and not having to worry about the temporary side of things
	 * 
	 * The order of code in playMediaInternal matters greatly for performance
	 * and logical reasons
	*/
	/** Plays the song BeatBox was closed on from where it was left */
	void resume_last() {
		var m = to_resume;
		to_resume = null;
		play_media(m, true);
		if(current_media != m) // its file is gone
			return;
		// resuming, not a new play: the stats were counted before
		int position = (int)m.resume_pos;
		if(position > 5) {
			queriedlastfm = true;
			play_counted = true;
		}
		if(position > 30)
			media_considered_played = true;
		if(m.length > 0 && position / (double)m.length > 0.90)
			added_to_play_count = true;
		play();
	}
	
	public void play_media(Media m, bool use_resume_pos) {
		to_resume = null; // another song was chosen
		if(m.isTemporary) {
			// takes the last preview's place (one id for all) and, being temporary, stays out of the database
			m.rowid = PREVIEW_MEDIA_ID;
			App.library.add_media(m);
			playMediaInternal(m, use_resume_pos);
		}
		else {
			playMediaInternal(m, use_resume_pos);
		}
	}
	
	void playMediaInternal(Media m, bool use_resume_pos) {
		if(m == null) {
			stop_playback();
		}
		
		// Save the previous media for later
		Media? old_media = null;
		if(media_active)
			old_media = current_media;
		if(old_media != null && old_media != m && old_media.uses_resume_pos)
			App.library.update_media(old_media, false, false, false); // where it was left goes to the database
		
		// set the current media info. Do this here rather than in info
		// so that this information is correct when media_played signal
		// is emitted
		current_media = m;
		App.info.current_track = App.info.get_track_info_from_media(m);
		App.info.current_album = App.info.get_album_info_from_media(m);
		App.info.current_artist = App.info.get_artist_info_from_media(m);
		
		// To avoid infinite loop, if we come across a song we already know does not exist then stop playback
		if(m.location_unknown) {
			if(File.new_for_uri(m.uri).query_exists()) {
				m.location_unknown = false;
				m.unique_status_image = null;
				media_found(m);
			}
			else { // to avoid infinite loop with repeat on, don't try to play next again
				stop_playback();
				return;
			}
		}
		
		// If it is a local media, check that the file exists
		var music_folder_uri = File.new_for_path(App.settings.main.music_folder).get_uri();
		if((App.settings.main.music_folder != "" && m.uri.has_prefix(music_folder_uri) && !GLib.File.new_for_uri(m.uri).query_exists())) {
			m.location_unknown = true;
			media_not_found(m);

			getNext(true);
			return;
		}
		else if(m.location_unknown) {
			m.unique_status_image = null;
			m.location_unknown = false;
		}
		
		// actually play the media asap
		if(!player.doing_gapless)
			player.setURI(m.uri, playing, use_resume_pos || m.uses_resume_pos);
		
		//update settings
		if(m.rowid != PREVIEW_MEDIA_ID)
			App.settings.main.last_media_playing = m.rowid;
		
		// Let everyone know that this media was played
		media_played(m, old_media);
		
		queriedlastfm = false;
		media_considered_played = false;
		added_to_play_count = false;
		play_counted = false;
		scrobbled_track = false;
		
		// if radio, we can't depend on current_position_update. do that stuff now.
		
		// TODO: This should be abstracted out
		if(App.playback.current_media is Station) {
			queriedlastfm = true;
			
			App.info.lastfm.post_now_playing();
			
			// always show notifications for the radio, since user likely does not know media
			App.window.show_notification(m.title, m.artist + "\n" + m.album, App.covers.get_album_art_from_media(m));
		}
		else {
			Timeout.add(3000, () => {
				if(App.playback.current_media != null && App.playback.current_media == m && m.rowid != PlaybackManager.PREVIEW_MEDIA_ID) {
					App.info.lastfm.fetch_current_similar_songs();
				}
				
				return false;
			});
		}
		
		/* if same media 1 second later...
		 * check for embedded art if need be (not loaded from on file) and use that
		 * check that the s.getAlbumArtPath() exists, if not set to "" and call updateCurrentMedia
		 * save old media's resume_pos
		 */
		Timeout.add(1000, post_media_played);
	}
	
	private bool post_media_played() {
		if(media_active) {
			Media m = current_media;
			
			apply_equalizer_preset();
			
			// potentially fix media length 
			int player_duration = (int)(player.getDuration()/1000000000);
			if(m.allow_fixing_length && player_duration > 1 && Math.fabs((double)(player_duration - m.length)) > 3) {
				m.length = (int)(player.getDuration()/1000000000);
				App.library.update_media(m, false, false, true);
			}
			
			if(!App.window.has_toplevel_focus) {
				App.window.show_notification(m.title, m.artist + "\n" + m.album, App.covers.get_album_art_from_media(m));
			}
		}
		
		return false;
	}
	
	public void stop_playback() {
		pause();
		
		Media was_playing = null;
		if(media_active)
			was_playing = current_media;
		
		App.settings.main.last_media_playing = 0;
		current_media = null;
		App.info.current_track = null;
		App.info.current_album = null;
		App.info.current_artist = null;
		
		queriedlastfm = false;
		media_considered_played = false;
		added_to_play_count = false;
		play_counted = false;
		
		playback_stopped(was_playing);
	}
	
	void internal_current_position_update(int64 position) {
		current_position_update(position); // pass it along before we potentially return
		
		if (!media_active)
			return;

		if (current_media.rowid == Media.PREVIEW_ROWID) // is preview
			return;

		double sec = ((double)position/1000000000);

		// the moment it really starts playing (not merely loaded, paused) it counts as a play
		if(playing && !play_counted) {
			play_counted = true;
			current_media.play_count++;
			current_media.last_played = (int)time_t();
			App.library.update_media(current_media, false, false, true);
		}

		// at about 3 seconds, update last fm. we wait to avoid excessive querying last.fm for info
		if(position > 3000000000 && !queriedlastfm) {
			queriedlastfm = true;
			
			App.info.lastfm.fetch_current_similar_songs();
			App.info.lastfm.post_now_playing();
			ListenBrainz.now_playing(current_media);
		}

		//at 30 seconds in, we consider the media as played
		if(position > 30000000000 && !media_considered_played) {
			media_considered_played = true;
			current_media.last_played = (int)time_t();

			// TODO: This should be abstracted out
			if(current_media is Podcast) { //podcast
				added_to_play_count = true;
			}

			App.library.update_media(current_media, false, false, true);

			// add to the already played list
			add_to_history(App.playback.current_media);

#if HAVE_ZEITGEIST
			var event = new Zeitgeist.Event.full (Zeitgeist.ZG_ACCESS_EVENT,
			                                       Zeitgeist.ZG_SCHEDULED_ACTIVITY, "app://beatbox.desktop",
			                                       new Zeitgeist.Subject.full(App.playback.current_media.uri,
			                                                                   Zeitgeist.NFO_AUDIO,
			                                                                   Zeitgeist.NFO_FILE_DATA_OBJECT,
			                                                                   "text/plain", "",
			                                                                   current_media.title, ""));
			new Zeitgeist.Log ().insert_events_no_reply(event);
#endif
		}

		// scrobble, by the rule Last.fm and ListenBrainz share: a song longer than
		// 30 seconds, once half of it or 4 minutes have played
		if(!scrobbled_track && current_media.length > 30 && (sec >= current_media.length / 2.0 || sec >= 240)) {
			scrobbled_track = true;
			int64 started_at = (int64)time_t() - (int64)sec;
			App.info.lastfm.scrobble(started_at);
			ListenBrainz.listened(current_media, started_at);
		}

		// past 80%, skipping to the next one is no longer a skip
		if((double)(sec/(double)current_media.length) > 0.80 && !added_to_play_count)
			added_to_play_count = true;
	}
	
	/********************* Equalizer ************************/
	/** The chosen preset, or in automatic mode the one named like the song's genre (else flat) */
	public void apply_equalizer_preset() {
		EqualizerPreset? chosen = null;
		if(App.settings.equalizer.equalizer_enabled && media_active) {
			bool automatic = App.settings.equalizer.auto_switch_preset;
			string genre = current_media.genre.down().strip();
			var presets = new LinkedList<EqualizerPreset>();
			presets.add_all(App.settings.equalizer.getDefaultPresets());
			presets.add_all(App.settings.equalizer.getCustomPresets());
			foreach(var p in presets) {
				if(p == null)
					continue;
				string name = p.name.down();
				// (an empty genre is "in" every name: it must not pick the first preset)
				bool genre_matches = genre != "" && (name in genre || genre in name);
				if(automatic ? genre_matches : p.name == App.settings.equalizer.selected_preset) {
					chosen = p;
					break;
				}
			}
		}
		for(int i = 0; i < 10; ++i)
			player.setEqualizerGain(i, chosen != null ? chosen.getGain(i) : 0);
	}
	
	public void setEqualizerGain(int index, int val) {
		player.setEqualizerGain(index, val);
	}
}
