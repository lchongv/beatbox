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
	
	public string label {
		set { first.label = value; second.label = value; restart(); }
	}
	
	public Marquee() {
		set_policy(PolicyType.EXTERNAL, PolicyType.NEVER);
		propagate_natural_height = true;
		shadow_type = ShadowType.NONE;
		
		box.halign = Align.CENTER; // centered while it fits
		box.add(first);
		box.add(second);
		add(box);
		first.show();
		box.show();
		second.set_no_show_all(true);
		
		add_tick_callback(tick);
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
	}
	
	bool tick(Widget w, Gdk.FrameClock clock) {
		int64 now = clock.get_frame_time();
		double dt = last_time == 0 ? 0 : (now - last_time) / 1000000.0;
		last_time = now;
		
		int natural;
		first.get_preferred_width(null, out natural);
		bool overflow = natural > get_allocated_width();
		second.set_visible(overflow);
		if(!overflow) {
			if(offset != 0) restart();
			return Source.CONTINUE;
		}
		
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
