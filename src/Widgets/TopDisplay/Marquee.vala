using Gtk;

/* A label that, when its text doesn't fit, scrolls around like a ticker band. */
public class BeatBox.Marquee : ScrolledWindow {
	const double SPEED = 35;   // px per second
	const double PAUSE = 2.0;  // seconds standing at the start
	const int GAP = 48;
	
	private Label first = new Label("");
	private Label second = new Label(""); // the copy that follows, only while scrolling
	private Box box = new Box(Orientation.HORIZONTAL, GAP);
	private string current = "";
	private double offset = 0;
	private double wait = PAUSE;
	private int64 last_time = 0;
	private uint tick_id = 0; // only while the text doesn't fit: a tick callback keeps the frame clock running
	
	public string label {
		set { first.label = value; second.label = value; restart(); }
	}
	
	public Marquee() {
		set_policy(PolicyType.EXTERNAL, PolicyType.NEVER);
		propagate_natural_height = true;
		has_frame = false;

		box.halign = Align.CENTER; // centered while it fits
		box.append(first);
		box.append(second);
		set_child(box);
		first.show();
		box.show();
		second.visible = false; // shown only while the text overflows
	}

	public override void size_allocate(int width, int height, int baseline) {
		base.size_allocate(width, height, baseline);
		check_overflow();
	}

	int natural_width() {
		int min, natural, min_base, natural_base;
		first.measure(Orientation.HORIZONTAL, -1, out min, out natural, out min_base, out natural_base);
		return natural;
	}

	void check_overflow() {
		bool overflow = natural_width() > get_width();
		second.set_visible(overflow);
		if(overflow && tick_id == 0) {
			last_time = 0;
			tick_id = add_tick_callback(tick);
		}
		else if(!overflow && tick_id != 0)
			stop();
	}
	
	void stop() {
		remove_tick_callback(tick_id);
		tick_id = 0;
		restart();
	}
	
	public void set_markup(string markup) {
		if(markup == current) // frequent status updates mustn't rewind the band
			return;
		current = markup;
		first.set_markup(markup);
		second.set_markup(markup);
		restart();
	}
	
	void restart() {
		offset = 0;
		wait = PAUSE;
		hadjustment.value = 0;
		if(get_realized()) check_overflow(); // the new text may fit, or not
	}
	
	bool tick(Widget w, Gdk.FrameClock clock) {
		int64 now = clock.get_frame_time();
		double dt = last_time == 0 ? 0 : (now - last_time) / 1000000.0;
		last_time = now;
		
		int natural = natural_width();
		if(wait > 0) {
			wait -= dt;
			return Source.CONTINUE;
		}
		offset += SPEED * dt;
		if(offset >= natural + GAP) // the copy is exactly where the first one began
			restart();
		hadjustment.value = offset;
		return Source.CONTINUE;
	}
}
