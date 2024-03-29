/* Database.vala
 *
 * Copyright (C) 2009 - 2015 Jerry Casiano
 *
 * This file is part of Font Manager.
 *
 * Font Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Font Manager is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Font Manager.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author:
 *        Jerry Casiano <JerryCasiano@gmail.com>
*/

namespace FontManager {

    private static Database? db = null;

    /* Error mapping/checking originally from Shotwell code */
    public errordomain DatabaseError {
        ERROR,
        BACKING,
        MEMORY,
        ABORT,
        LIMITS,
        TYPESPEC
    }

    /*
     * Thin wrapper to make sqlite easier to work with?
     */
    public class Database : Object {

        public Sqlite.Database db;
        public Sqlite.Statement stmt;

        public string? search {
            get {
                return _search;
            }
            set {
                if (value != null)
                    _search = """WHERE %s""".printf(value);
                else
                    _search = "";
            }
        }

        public string? sort {
            get {
                return _sort;
            }
            set {
                if (value != null)
                    _sort = """ORDER BY %s""".printf(value);
                else
                    _sort = "";
            }
        }

        public string file { get; set; default = ":memory:"; }
        public string table { get; set; default = "sqlite_master"; }
        public string select { get; set; default = "*"; }
        public int limit { get; set; default = -1; }
        public bool unique { get; set; default = false; }
        public int result { get; protected set; default = Sqlite.OK; }

        private bool in_transaction = false;
        protected string _search = "";
        protected string _sort = "";

        ~ Database () {
            close();
        }

        public int get_version () throws DatabaseError {
            execute_query("PRAGMA user_version;");
            if (stmt.step() == Sqlite.ROW)
                return stmt.column_int(0);
            return 0;
        }

        public void set_version (int version) throws DatabaseError {
            string sql = "PRAGMA user_version = %i;".printf(version);
            execute_query(sql);
            check_result(stmt.step(), "set version", Sqlite.DONE);
            return;
        }


        public void open () throws DatabaseError ensures (db != null) {
            if (db != null)
                return;
            check_result(Sqlite.Database.open_v2(file,
                                                   out db,
                                                   Sqlite.OPEN_READWRITE | Sqlite.OPEN_CREATE,
                                                   null),
                                                   "open_v2");
            return;
        }

        public void close () {
            stmt = null;
            db = null;
            return;
        }

        public void reset () {
            table = "sqlite_master";
            select = "*";
            limit = -1;
            unique = false;
            search = null;
            sort = null;
        }

        public string build_select_query () {
            var builder = new StringBuilder("SELECT");
            if (unique)
                builder_append(builder, "DISTINCT");
            builder_append(builder, select);
            builder_append(builder, "FROM");
            builder_append(builder, table);
            builder_append(builder, search);
            builder_append(builder, sort);
            if (limit > 0)
                builder_append(builder, "LIMIT %s".printf(limit.to_string()));
            return builder.str;
        }

        public void begin_transaction () throws DatabaseError {
            if (in_transaction)
                return;
            open();
            check_result(db.exec("BEGIN"), "begin_transaction");
            in_transaction = true;
            return;
        }

        public void commit_transaction () throws DatabaseError {
            if (!in_transaction)
                throw new DatabaseError.ERROR("Not in transaction - nothing to commit.");
            check_result(db.exec("COMMIT"), "commit_transaction");
            close();
            in_transaction = false;
            return;
        }

        public void vacuum () throws DatabaseError {
            open();
            check_result(db.exec("VACUUM"), "vacuum");
            close();
            return;
        }

        public void execute_query (string? query = null) throws DatabaseError {
            open();
            string? sql = query;
            if (sql == null)
                sql = build_select_query();
            Logger.verbose("SQLite : %s", sql);
            check_result(db.prepare_v2(sql, -1, out stmt), "prepare_v2", Sqlite.OK);
            return;
        }

        public void remove (string condition) throws DatabaseError {
            execute_query("""DELETE FROM %s WHERE %s""".printf(table, condition));
            check_result(stmt.step(), "remove");
            close();
            return;
        }

        public int get_row_count () throws DatabaseError {
            open();
            check_result(db.prepare_v2("""SELECT COUNT(*) FROM %s""".printf(table), -1, out stmt),
                        "get_row_count",
                        Sqlite.OK);
            check_result(stmt.step(), "get_row_count");
            int res = stmt.column_int(0);
            close();
            return res;
        }

        public Iterator iterator () {
            return new Iterator(this);
        }

            public class Iterator {
                private Database db;
                public Iterator (Database db) {
                    this.db = db;
                }

                ~ Iterator () {
                    db.close();
                    db = null;
                }

                public unowned Sqlite.Statement? next_value () {
                    if (db.stmt.step() != Sqlite.ROW)
                        db.stmt = null;
                    return db.stmt;
                }

            }

        public void check_result (int result, string method, int expected = -1)
        throws DatabaseError {
            this.result = result;
            string msg = "SQLite : (%s) [%d] - %s\n".printf(method, result, db.errmsg());
            if (expected != -1 && expected != result)
                throw new DatabaseError.ERROR(msg);

            switch (result) {
                case Sqlite.OK:
                case Sqlite.DONE:
                case Sqlite.ROW:
                    return;

                case Sqlite.PERM:
                case Sqlite.BUSY:
                case Sqlite.READONLY:
                case Sqlite.IOERR:
                case Sqlite.CORRUPT:
                case Sqlite.CANTOPEN:
                case Sqlite.NOLFS:
                case Sqlite.AUTH:
                case Sqlite.FORMAT:
                case Sqlite.NOTADB:
                    throw new DatabaseError.BACKING(msg);

                case Sqlite.NOMEM:
                    throw new DatabaseError.MEMORY(msg);

                case Sqlite.ABORT:
                case Sqlite.LOCKED:
                case Sqlite.INTERRUPT:
                    throw new DatabaseError.ABORT(msg);

                case Sqlite.FULL:
                case Sqlite.EMPTY:
                case Sqlite.TOOBIG:
                case Sqlite.CONSTRAINT:
                case Sqlite.RANGE:
                    throw new DatabaseError.LIMITS(msg);

                case Sqlite.SCHEMA:
                case Sqlite.MISMATCH:
                    throw new DatabaseError.TYPESPEC(msg);

                case Sqlite.ERROR:
                case Sqlite.INTERNAL:
                case Sqlite.MISUSE:
                default:
                    throw new DatabaseError.ERROR(msg);
            }
        }

    }

    private Database get_database() throws DatabaseError {
        if (db != null)
            return db;
        db = new Database();
        db.file = get_database_file();
        db.execute_query(CREATE_SQL);
        db.check_result(db.stmt.step(), "Initialize database if needed", Sqlite.DONE);
        db.close();
        return db;
    }

    private string get_database_file () {
        string dirpath = Path.build_filename(Environment.get_user_cache_dir(), NAME);
        string filepath = Path.build_filename(dirpath, "%s.sqlite".printf(NAME));
        DirUtils.create_with_parents(dirpath, 0755);
        return filepath;
    }

    private void sync_fonts_table (Database db,
                                    Gee.ArrayList <FontConfig.Font> installed_fonts,
                                    ProgressCallback? progress = null)
    throws DatabaseError {
        Logger.verbose("Starting database synchronization : Font table");
        int processed = 0;
        int total = installed_fonts.size;
        var known_files = get_known_files(db);
        db.begin_transaction();
        db.execute_query("""INSERT OR REPLACE INTO Fonts VALUES (NULL,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);""");
        foreach (var font in installed_fonts) {
            if (!(font.filepath in known_files)) {
                var fileinfo = new FontInfo.from_filepath(font.filepath, font.index);
                db.check_result(db.stmt.bind_text(1, font.family), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(2, font.style), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_int(3, font.slant), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_int(4, font.weight), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_int(5, font.width), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_int(6, font.spacing), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_int(7, font.index), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(8, font.filepath), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_int(9, fileinfo.owner), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(10, fileinfo.filetype), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(11, fileinfo.filesize), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(12, fileinfo.checksum), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(13, fileinfo.version), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(14, fileinfo.psname), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(15, fileinfo.description), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(16, fileinfo.vendor), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(17, fileinfo.copyright), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(18, fileinfo.license_type), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(19, fileinfo.license_data), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(20, fileinfo.license_url), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(21, fileinfo.panose), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.bind_text(22, font.description), "bind_*", Sqlite.OK);
                db.check_result(db.stmt.step(), "apply_bindings", Sqlite.DONE);
            }
            processed++;
            if (progress != null)
                progress(font.to_string(), processed, total);
            db.stmt.reset();
        }
        db.commit_transaction();
        Logger.verbose("Database synchronization complete : Font table");
        return;
    }

    private Gee.HashSet <string> get_known_files (Database db) {
        var results = new Gee.HashSet <string> ();
        db.reset();
        db.table = "Fonts";
        db.select = "filepath";
        db.unique = true;
        try {
            db.execute_query();
            foreach (var row in db)
                results.add(row.column_text(0));
        } catch (DatabaseError e) {
            critical("Database Error : %s", e.message);
        }
        db.close();
        return results;
    }


    private void get_matching_families_and_fonts (Database db,
                                                    Gee.HashSet <string> families,
                                                    Gee.HashSet <string> descriptions,
                                                    string? search = null)
    throws DatabaseError {
        db.reset();
        db.table = "Fonts";
        db.select = "family, font_description";
        db.search = search;
        db.unique = true;
        db.execute_query();
        var active = FontConfig.list_families();
        foreach (var row in db) {
            if (row.column_text(0) in active) {
                families.add(row.column_text(0));
                descriptions.add(row.column_text(1));
            }
        }
        db.close();
        return;
    }

    private Gee.HashMap <string, string> get_user_filemap (Database db)
    throws DatabaseError {
        var res = new Gee.HashMap <string, string> ();
        db.reset();
        db.table = "Fonts";
        db.select = "font_description, filepath";
        db.search = "owner=\"0\" AND filepath LIKE \"%s%\"".printf(get_user_font_dir());
        db.unique = true;
        db.execute_query();
        foreach (var row in db)
            res[row.column_text(0)] = row.column_text(1);
        db.close();
        return res;
    }

    private FontInfo? get_fontinfo_from_db_entry (Database db, string filepath)
    throws DatabaseError {
        db.reset();
        db.table = "Fonts";
        db.select = "*";
        db.search = "filepath=\"%s\"".printf(filepath);
        db.unique = true;
        db.execute_query();
        if (db.stmt.step() != Sqlite.ROW)
            return null;
        var res = new FontInfo();
        unowned ObjectClass obj_cls = res.get_class();
        int cols = db.stmt.column_count ();
        var val = Value(typeof(string));
        for (int i = 0; i < cols; i++) {
            if (db.stmt.column_type(i) != Sqlite.TEXT)
                continue;
            string name = db.stmt.column_name(i);
            val = db.stmt.column_text(i);
            if (obj_cls.find_property(name) != null)
                ((Object) res).set_property(name, val);
        }
        val.unset();
        return res;
    }



}
