/* Sources.vala
 *
 * Copyright © ? Jerry Casiano
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

namespace FontConfig {

    public class Sources : Gee.HashSet <FontSource> {

        public signal void changed ();

        public string? target_file {
            get {
                return _target_file;
            }
            set {
                _target_file = Path.build_filename(get_config_dir(), value);
            }
        }

        public string? target_element { get; set; default = null; }
        public bool update_required {
            get {
                return _dirty;
            }
            set {
                _dirty = value;
                this.changed();
            }
        }

        string? _target_file = null;
        internal bool _dirty = false;

        public Sources () {
            target_element = "source";
            target_file = "UserSources";
        }

        public new bool contains (string path) {
            foreach (var source in this)
                if (source.path.contains(path))
                    return true;
            return false;
        }

        public void update () {
            foreach (var source in this)
                source.update();
            this.changed();
            return;
        }

        public new bool add (FontSource source) {
            source.notify["active"].connect(() => { update_required = true; });
            return base.add(source);
        }

        public new bool remove (FontSource source) {
            source.available = false;
            update_required = true;
            return base.remove(source);
        }

        public bool init ()
        requires (target_file != null && target_element != null) {

            {
                File file = File.new_for_path(target_file);
                if (!file.query_exists())
                    return false;
            }

            Xml.Parser.init();

            Xml.Doc * doc = Xml.Parser.parse_file(target_file);
            if (doc == null) {
                /* File not found */
                Xml.Parser.cleanup();
                return false;
            }

            Xml.Node * root = doc->get_root_element();
            if (root == null) {
                /* Empty doc */
                delete doc;
                Xml.Parser.cleanup();
                return false;
            }

            parse(root);

            delete doc;
            Xml.Parser.cleanup();
            return true;
        }

        public void save ()
        requires (target_file != null && target_element != null) {
            var writer = new Xml.TextWriter.filename(target_file);
            writer.set_indent(true);
            writer.set_indent_string("  ");
            writer.start_document();
            writer.write_comment(_(" Generated by Font Manager. Do NOT edit this file. "));
            writer.start_element("UserSources");
            write_node(writer);
            writer.end_element();
            writer.end_document();
            writer.flush();
            return;
        }

        protected void parse (Xml.Node * root) {
            parse_node(root->children);
        }

        protected void write_node (Xml.TextWriter writer) {
            foreach (var source in this)
                writer.write_element(target_element, Markup.escape_text(source.path.strip()));
            return;
        }

        protected void parse_node (Xml.Node * node) {
            for (Xml.Node * iter = node; iter != null; iter = iter->next) {
                /* Spaces between tags are also nodes, discard them */
                if (iter->type != Xml.ElementType.ELEMENT_NODE)
                    continue;
                string content = iter->get_content();
                if (content == null)
                    continue;
                content = content.strip();
                if (content == "")
                    continue;
                else {
                    var source = new FontSource(File.new_for_path(content));
                    this.add(source);
                }
            }
            return;
        }

    }

}
