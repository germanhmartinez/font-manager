/* FontModel.vala
 *
 * Copyright © 2009 - 2014 Jerry Casiano
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author:
 *  Jerry Casiano <JerryCasiano@gmail.com>
 */

namespace FontManager {

    public enum FontModelColumn {
        OBJECT,
        DESCRIPTION,
        COUNT,
        N_COLUMNS
    }

    public class FontModel : Gtk.TreeStore {

        public FontConfig.Families families {
            get {
                return _families;
            }
            set {
                _families = value;
                this.init();
            }
        }

        internal weak FontConfig.Families _families;

        construct {
            set_column_types({typeof(Object), typeof(string), typeof(int)});
        }

        public void update (Filter? filter = null) {
            this.clear();
            if (families == null)
                return;
            bool visible = true;
            Gee.HashSet <string> contents = null;
            foreach(var entry in families.list()) {
                var family = families[entry];
                if (filter != null) {
                    if (contents == null)
                        if (filter is Collection)
                            contents = ((Collection) filter).get_full_contents();
                        else
                            contents = filter.families;
                    visible = (family.name in contents);
                }
                if (visible) {
                    Gtk.TreeIter iter;
                    this.append(out iter, null);
                    this.set(iter, 0, family, 1, family.description, 2, family.faces.size,  -1);
                    foreach(var face in family.list_faces()) {
                        visible = true;
                        if (filter != null && filter is Category)
                            if (!(face.description in ((Category) filter).descriptions))
                                visible = false;
                        if (visible) {
                            Gtk.TreeIter _iter;
                            this.append(out _iter, iter);
                            this.set(_iter, 0, face, 1, face.description, -1);
                        }
                    }
                }
            }
            contents = null;
            return;
        }

        public void init () {
            this.update();
            return;
        }

    }

}
