/*
 * Minimal replacement for the long-dead SQLHeavy library, built on plain
 * sqlite3. Only implements the subset BeatBox actually uses.
 */

[GIR (visible = false)] // internal: plugins don't see it
namespace SQLHeavy {
	public errordomain Error {
		ERROR
	}

	public class Database : GLib.Object {
		internal Sqlite.Database db;

		public Database (string path) throws SQLHeavy.Error {
			if (Sqlite.Database.open_v2 (path, out db) != Sqlite.OK)
				throw new Error.ERROR ("Could not open %s: %s", path, db.errmsg ());
		}

		public void execute (string sql) throws SQLHeavy.Error {
			string errmsg;
			if (db.exec (sql, null, out errmsg) != Sqlite.OK)
				throw new Error.ERROR ("%s", errmsg);
		}

		public Transaction begin_transaction () throws SQLHeavy.Error {
			return new Transaction (this);
		}
	}

	public class Transaction : GLib.Object {
		Database database;
		bool done = false;

		internal Transaction (Database database) throws SQLHeavy.Error {
			this.database = database;
			database.execute ("BEGIN TRANSACTION;");
		}

		public Query prepare (string sql) throws SQLHeavy.Error {
			return new Query (database, sql);
		}

		public void commit () throws SQLHeavy.Error {
			done = true;
			database.execute ("COMMIT;");
		}

		~Transaction () {
			if (!done) {
				try { database.execute ("ROLLBACK;"); } catch (SQLHeavy.Error e) {}
			}
		}
	}

	public class Query : GLib.Object {
		Database database;
		internal Sqlite.Statement stmt;

		public Query (Database database, string sql) throws SQLHeavy.Error {
			this.database = database;
			if (database.db.prepare_v2 (sql, -1, out stmt) != Sqlite.OK)
				throw new Error.ERROR ("%s", database.db.errmsg ());
		}

		int index (string name) throws SQLHeavy.Error {
			stmt.reset (); // allows re-binding a statement that was already executed
			int i = stmt.bind_parameter_index (name);
			if (i == 0)
				throw new Error.ERROR ("Unknown parameter %s", name);
			return i;
		}

		public void set_string (string name, string? val) throws SQLHeavy.Error {
			stmt.bind_text (index (name), val ?? "");
		}

		public void set_int (string name, int val) throws SQLHeavy.Error {
			stmt.bind_int (index (name), val);
		}

		public void set_int64 (string name, int64 val) throws SQLHeavy.Error {
			stmt.bind_int64 (index (name), val);
		}

		public QueryResult execute () throws SQLHeavy.Error {
			stmt.reset ();
			return new QueryResult (this);
		}

		internal void check (int rc) throws SQLHeavy.Error {
			if (rc != Sqlite.ROW && rc != Sqlite.DONE)
				throw new Error.ERROR ("%s", database.db.errmsg ());
		}
	}

	public class QueryResult : GLib.Object {
		Query query;
		public bool finished { get; private set; }

		internal QueryResult (Query query) throws SQLHeavy.Error {
			this.query = query;
			next ();
		}

		public bool next () throws SQLHeavy.Error {
			int rc = query.stmt.step ();
			query.check (rc);
			finished = (rc != Sqlite.ROW);
			return !finished;
		}

		public string fetch_string (int field) throws SQLHeavy.Error {
			return query.stmt.column_text (field) ?? "";
		}

		public int fetch_int (int field) throws SQLHeavy.Error {
			return query.stmt.column_int (field);
		}

		public int64 fetch_int64 (int field) throws SQLHeavy.Error {
			return query.stmt.column_int64 (field);
		}
	}
}
