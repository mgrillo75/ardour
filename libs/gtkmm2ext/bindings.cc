/*
 * Copyright (C) 2010-2019 Paul Davis <paul@linuxaudiosystems.com>
 * Copyright (C) 2015-2018 Robin Gareus <robin@gareus.org>
 * Copyright (C) 2017 Ben Loftis <ben@harrisonconsoles.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <iostream>

#include "pbd/gstdio_compat.h"
#include <ytkmm/accelmap.h>
#include <ytkmm/uimanager.h>

#include "pbd/convert.h"
#include "pbd/debug.h"
#include "pbd/error.h"
#include "pbd/replace_all.h"
#include "pbd/xml++.h"

#include "gtkmm2ext/actions.h"
#include "gtkmm2ext/bindings.h"
#include "gtkmm2ext/debug.h"
#include "gtkmm2ext/keyboard.h"
#include "gtkmm2ext/utils.h"

#include "pbd/i18n.h"

using namespace std;
using namespace Glib;
using namespace Gtk;
using namespace Gtkmm2ext;
using namespace PBD;

list<Bindings*> Bindings::bindings; /* global. Gulp */
PBD::Signal<void(Bindings*)> Bindings::BindingsChanged;
int Bindings::_drag_active = 0;

template <typename IteratorValueType>
struct ActionNameRegistered
{
	ActionNameRegistered(std::string const& name)
		: action_name(name)
	{}

	bool operator()(IteratorValueType elem) const {
		return elem.second.action_name == action_name;
	}
	std::string const& action_name;
};

MouseButton::MouseButton (uint32_t state, uint32_t keycode)
{
	uint32_t ignore = ~Keyboard::RelevantModifierKeyMask;

	/* this is a slightly weird test that relies on
	 * gdk_keyval_is_{upper,lower}() returning true for keys that have no
	 * case-sensitivity. This covers mostly non-alphanumeric keys.
	 */

	if (gdk_keyval_is_upper (keycode) && gdk_keyval_is_lower (keycode)) {
		/* key is not subject to case, so ignore SHIFT
		 */
		ignore |= GDK_SHIFT_MASK;
	}

	_val = (state & ~ignore);
	_val <<= 32;
	_val |= keycode;
};

bool
MouseButton::make_button (const string& str, MouseButton& b)
{
	int s = 0;

	if (str.find ("Primary") != string::npos) {
		s |= Keyboard::PrimaryModifier;
	}

	if (str.find ("Secondary") != string::npos) {
		s |= Keyboard::SecondaryModifier;
	}

	if (str.find ("Tertiary") != string::npos) {
		s |= Keyboard::TertiaryModifier;
	}

	if (str.find ("Level4") != string::npos) {
		s |= Keyboard::Level4Modifier;
	}

	string::size_type lastmod = str.find_last_of ('-');
	uint32_t button_number;

	if (lastmod == string::npos) {
		button_number = PBD::atoi (str);
	} else {
		button_number = PBD::atoi (str.substr (lastmod+1));
	}

	b = MouseButton (s, button_number);
	return true;
}

string
MouseButton::name () const
{
	int s = state();

	string str;

	if (s & Keyboard::PrimaryModifier) {
		str += "Primary";
	}
	if (s & Keyboard::SecondaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += "Secondary";
	}
	if (s & Keyboard::TertiaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += "Tertiary";
	}
	if (s & Keyboard::Level4Modifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += "Level4";
	}

	if (!str.empty()) {
		str += '-';
	}

	char buf[16];
	snprintf (buf, sizeof (buf), "%u", button());
	str += buf;

	return str;
}

/*================================ KeyboardKey ================================*/
KeyboardKey::KeyboardKey (uint32_t state, uint32_t keycode)
{
	uint32_t ignore = ~Keyboard::RelevantModifierKeyMask;

	_val = (state & ~ignore);
	_val <<= 32;
	_val |= keycode;
}

string
KeyboardKey::display_label () const
{
	if (key() == 0) {
		return string();
	}

	/* This magically returns a string that will display the right thing
	 *  on all platforms, notably the command key on OS X.
	 */

	uint32_t mod = state();

	return gtk_accelerator_get_label (key(), (GdkModifierType) mod);
}

string
KeyboardKey::name () const
{
	int s = state();

	string str;

	if (s & Keyboard::PrimaryModifier) {
		str += "Primary";
	}
	if (s & Keyboard::SecondaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += "Secondary";
	}
	if (s & Keyboard::TertiaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += "Tertiary";
	}
	if (s & Keyboard::Level4Modifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += "Level4";
	}

	if (!str.empty()) {
		str += '-';
	}

	char const *gdk_name = gdk_keyval_name (key());

	if (gdk_name) {
		str += gdk_name;
	} else {
		/* fail! */
		return string();
	}

	return str;
}

string
KeyboardKey::native_name () const
{
	int s = state();

	string str;

	if (s & Keyboard::PrimaryModifier) {
		str += Keyboard::primary_modifier_name ();
	}
	if (s & Keyboard::SecondaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += Keyboard::secondary_modifier_name ();
	}
	if (s & Keyboard::TertiaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += Keyboard::tertiary_modifier_name ();
	}
	if (s & Keyboard::Level4Modifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += Keyboard::level4_modifier_name ();
	}

	if (!str.empty()) {
		str += '-';
	}

	char const *gdk_name = gdk_keyval_name (key());

	if (gdk_name) {
		str += gdk_name;
	} else {
		/* fail! */
		return string();
	}

	return str;
}

string
KeyboardKey::native_short_name () const
{
	int s = state();

	string str;

	if (s & Keyboard::PrimaryModifier) {
		str += Keyboard::primary_modifier_short_name ();
	}
	if (s & Keyboard::SecondaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += Keyboard::secondary_modifier_short_name ();
	}
	if (s & Keyboard::TertiaryModifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += Keyboard::tertiary_modifier_short_name ();
	}
	if (s & Keyboard::Level4Modifier) {
		if (!str.empty()) {
			str += '-';
		}
		str += Keyboard::level4_modifier_short_name ();
	}

	if (!str.empty()) {
		str += '-';
	}

	char const *gdk_name = gdk_keyval_name (key());

	if (gdk_name) {
		str += gdk_name;
	} else {
		/* fail! */
		return string();
	}

	return str;
}

bool
KeyboardKey::make_key (const string& str, KeyboardKey& k)
{
	int s = 0;

	if (str.find ("Primary") != string::npos) {
		s |= Keyboard::PrimaryModifier;
	}

	if (str.find ("Secondary") != string::npos) {
		s |= Keyboard::SecondaryModifier;
	}

	if (str.find ("Tertiary") != string::npos) {
		s |= Keyboard::TertiaryModifier;
	}

	if (str.find ("Level4") != string::npos) {
		s |= Keyboard::Level4Modifier;
	}

	/* since all SINGLE key events keycodes are changed to lower case
	 * before looking them up, make sure we only store lower case here. The
	 * Shift part will be stored in the modifier part of the KeyboardKey.
	 *
	 * And yes Mildred, this doesn't cover CapsLock cases. Oh well.
	 */

	string actual;

	string::size_type lastmod = str.find_last_of ('-');

	if (lastmod != string::npos) {
		actual = str.substr (lastmod+1);
	}
	else {
		actual = str;
	}

	if (actual.size() == 1) {
		actual = PBD::downcase (actual);
	}

	guint keyval;
	keyval = gdk_keyval_from_name (actual.c_str());

	if (keyval == GDK_VoidSymbol || keyval == 0) {
		return false;
	}

	k = KeyboardKey (s, keyval);

	return true;
}

/*================================= Bindings =================================*/
Bindings::Bindings (std::string const& name)
	: _parent (nullptr)
	, _name (name)
{
	bindings.push_back (this);
}

Bindings::Bindings (std::string const & name, Bindings & other)
	: _parent (&other)
	, _name (name)
{
	copy_from_parent (false);

	BindingsChanged.connect_same_thread (bc, std::bind (&Bindings::parent_changed, this, _1));

	bindings.push_back (this);
}

Bindings::~Bindings()
{
	bindings.remove (this);
}

string
Bindings::ardour_action_name (RefPtr<Action> action)
{
	/* Skip "<Actions>/" */
	return action->get_accel_path ().substr (10);
}

KeyboardKey
Bindings::get_binding_for_action (RefPtr<Action> action, Operation& op)
{
	const string action_name = ardour_action_name (action);

	for (KeybindingMap::iterator k = press_bindings.begin(); k != press_bindings.end(); ++k) {

		/* option one: action has already been associated with the
		 * binding
		 */

		if (k->second.action == action) {
			return k->first;
		}

		/* option two: action name matches, so lookup the action,
		 * setup the association while we're here, and return the binding.
		 */

		if (k->second.action_name == action_name) {
			k->second.action = ActionManager::get_action (action_name, false);
			return k->first;
		}

	}

	for (KeybindingMap::iterator k = release_bindings.begin(); k != release_bindings.end(); ++k) {

		/* option one: action has already been associated with the
		 * binding
		 */

		if (k->second.action == action) {
			return k->first;
		}

		/* option two: action name matches, so lookup the action,
		 * setup the association while we're here, and return the binding.
		 */

		if (k->second.action_name == action_name) {
			k->second.action = ActionManager::get_action (action_name, false);
			return k->first;
		}

	}

	return KeyboardKey::null_key();
}

void
Bindings::reassociate ()
{
	dissociate ();
	associate ();
}

bool
Bindings::empty_keys() const
{
	return press_bindings.empty() && release_bindings.empty();
}

bool
Bindings::empty_mouse () const
{
	return button_press_bindings.empty() && button_release_bindings.empty();
}

bool
Bindings::empty() const
{
	return empty_keys() && empty_mouse ();
}

bool
Bindings::activate (KeyboardKey kb, Operation op)
{
	KeybindingMap& kbm = get_keymap (op);

	/* if shift was pressed, GDK will send us (e.g) 'E' rather than 'e'.
	   Our bindings all use the lower case character/keyname, so switch
	   to the lower case before doing the lookup.
	*/

	KeyboardKey unshifted (kb.state(), gdk_keyval_to_lower (kb.key()));

	KeybindingMap::iterator k = kbm.find (unshifted);

	if (k == kbm.end()) {
		/* no entry for this key in the state map */
		DEBUG_TRACE (DEBUG::Bindings, string_compose ("no binding for %1 (of %2) within %3\n", unshifted, kbm.size(), _name));
		return false;
	}

	RefPtr<Action> action;

	if (k->second.action) {
		action = k->second.action;
	} else {
		action = ActionManager::get_action (k->second.action_name, false);
	}

	/* bindings cannot be used during drags */

	if (_drag_active) {
		/* sadly we need to special case one possible action, because
		   Escape is used to break drags.
		*/
		if (!action || action->get_name() != _("Escape")) {
			return true;
		}
	}

	if (action) {
		/* lets do it ... */
		if (action->get_sensitive()) {
			DEBUG_TRACE (DEBUG::Bindings, string_compose ("binding for %1: %2 within %3\n", unshifted, k->second.action_name, _name));
			action->activate ();
		} else {
			DEBUG_TRACE (DEBUG::Bindings, string_compose ("binding for %1: %2 - insensitive, skipped within %3\n", unshifted, k->second.action_name, _name));
			return false;
		}
	} else {
		DEBUG_TRACE (DEBUG::Bindings, string_compose ("binding for %1 is known but has no action within %2\n", unshifted, _name));
	}
	/* return true even if the action could not be found */

	return true;
}

void
Bindings::relativize ()
{
	for (auto & [key,action_info] : press_bindings) {
		action_info.action_name = _name + action_info.action_name;
	}
	for (auto & [key,action_info] : release_bindings) {
		action_info.action_name = _name + action_info.action_name;
	}
	for (auto & [mb,action_info] : button_press_bindings) {
		action_info.action_name = _name + action_info.action_name;
	}
	for (auto & [mb,action_info] : button_release_bindings) {
		action_info.action_name = _name + action_info.action_name;
	}
}

void
Bindings::associate (bool force)
{
	KeybindingMap::iterator k;

	for (k = press_bindings.begin(); k != press_bindings.end(); ++k) {
		k->second.action = ActionManager::get_action (k->second.action_name, false);
		if (k->second.action) {
			push_to_gtk (k->first, k->second.action);
		}
	}

	for (k = release_bindings.begin(); k != release_bindings.end(); ++k) {
		k->second.action = ActionManager::get_action (k->second.action_name, false);
		/* no working support in GTK for release bindings */
	}

	MouseButtonBindingMap::iterator b;

	for (b = button_press_bindings.begin(); b != button_press_bindings.end(); ++b) {
		b->second.action = ActionManager::get_action (b->second.action_name, false);
	}

	for (b = button_release_bindings.begin(); b != button_release_bindings.end(); ++b) {
		b->second.action = ActionManager::get_action (b->second.action_name, false);
	}
}

void
Bindings::dissociate ()
{
	KeybindingMap::iterator k;

	for (k = press_bindings.begin(); k != press_bindings.end(); ++k) {
		k->second.action.clear ();
	}
	for (k = release_bindings.begin(); k != release_bindings.end(); ++k) {
		k->second.action.clear ();
	}
}

void
Bindings::copy_from_parent (bool assoc)
{
	assert (_parent);
	press_bindings.clear ();
	release_bindings.clear ();

	_parent->clone_press (press_bindings);
	_parent->clone_release (release_bindings);

	dissociate ();
	relativize ();

	if (assoc) {
		associate (true);
	}
}

void
Bindings::parent_changed (Bindings* changed)
{
	if (_parent != changed) {
		return;
	}

	press_bindings.clear();
	release_bindings.clear();

	copy_from_parent (true);
}

void
Bindings::clone_press (KeybindingMap& target) const
{
	clone_kbd_bindings (press_bindings, target);
}

void
Bindings::clone_release (KeybindingMap& target) const
{
	clone_kbd_bindings (release_bindings, target);
}

void
Bindings::clone_kbd_bindings (KeybindingMap const & src, KeybindingMap& target) const
{
	target = src;
}

void
Bindings::push_to_gtk (KeyboardKey kb, RefPtr<Action> what)
{
	/* GTK has the useful feature of showing key bindings for actions in
	 * menus. As of August 2015, we have no interest in trying to
	 * reimplement this functionality, so we will use it even though we no
	 * longer use GTK accelerators for handling key events. To do this, we
	 * need to make sure that there is a fully populated GTK AccelMap set
	 * up with all bindings/actions.
	 */

	Gtk::AccelKey gtk_key;
	bool entry_exists = Gtk::AccelMap::lookup_entry (what->get_accel_path(), gtk_key);

	if (!entry_exists) {

		/* there is a trick happening here. It turns out that
		 * gtk_accel_map_add_entry() performs no validation checks on
		 * the accelerator keyval. This means we can use it to define
		 * ANY accelerator, even if they violate GTK's rules
		 * (e.g. about not using navigation keys). This works ONLY when
		 * the entry in the GTK accelerator map has not already been
		 * added. The entries will be added by the GTK UIManager when
		 * building menus, so this code must be called before that
		 * happens.
		 */


		int mod = kb.state();

		Gtk::AccelMap::add_entry (what->get_accel_path(), kb.key(), (Gdk::ModifierType) mod);
	}
}

bool
Bindings::replace (KeyboardKey kb, Operation op, string const & action_name, bool can_save)
{
	if (is_registered(op, action_name)) {
		/* never save after the remove, because if can_save is true, we
		   will save after we add the new binding.
		*/
		remove (op, action_name, false);
	}

	/* XXX need a way to get the old group name */
	add (kb, op, action_name, 0, can_save);

	return true;
}

bool
Bindings::add (KeyboardKey kb, Operation op, string const& action_name, XMLProperty const* group, bool can_save)
{
	if (is_registered (op, action_name)) {
		return false;
	}

	KeybindingMap& kbm = get_keymap (op);
	if (group) {
		KeybindingMap::value_type new_pair = make_pair (kb, ActionInfo (action_name, group->value()));
		(void) kbm.insert (new_pair).first;
	} else {
		KeybindingMap::value_type new_pair = make_pair (kb, ActionInfo (action_name));
		(void) kbm.insert (new_pair).first;
	}

	DEBUG_TRACE (DEBUG::Bindings, string_compose ("%5: add binding between %1 (%3) and %2, group [%3]\n",
	                                              kb, action_name, (group ? group->value() : string()), op, _name));

	if (can_save) {
		Keyboard::keybindings_changed ();
	}

	BindingsChanged (this); /* EMIT SIGNAL */
	return true;
}

bool
Bindings::remove (Operation op, std::string const& action_name, bool can_save)
{
	bool erased_action = false;
	KeybindingMap& kbm = get_keymap (op);

	for (KeybindingMap::iterator k = kbm.begin(); k != kbm.end(); ++k) {
		if (k->second.action_name == action_name) {
			kbm.erase (k);
			erased_action = true;
			break;
		}
	}

	if (!erased_action) {
		return erased_action;
	}

	if (can_save) {
		Keyboard::keybindings_changed ();
	}

	BindingsChanged (this); /* EMIT SIGNAL */
	return erased_action;
}


bool
Bindings::activate (MouseButton bb, Operation op)
{
	MouseButtonBindingMap& bbm = get_mousemap(op);

	MouseButtonBindingMap::iterator b = bbm.find (bb);

	if (b == bbm.end()) {
		/* no entry for this key in the state map */
		return false;
	}

	RefPtr<Action> action;

	if (b->second.action) {
		action = b->second.action;
	} else {
		action = ActionManager::get_action (b->second.action_name, false);
	}

	if (action) {
		/* lets do it ... */
		DEBUG_TRACE (DEBUG::Bindings, string_compose ("activating action %1\n", ardour_action_name (action)));
		action->activate ();
	}

	/* return true even if the action could not be found */

	return true;
}

void
Bindings::add (MouseButton bb, Operation op, string const& action_name, XMLProperty const* /*group*/)
{
	MouseButtonBindingMap& bbm = get_mousemap(op);

	MouseButtonBindingMap::value_type newpair (bb, ActionInfo (action_name));
	bbm.insert (newpair);
}

void
Bindings::remove (MouseButton bb, Operation op)
{
	MouseButtonBindingMap& bbm = get_mousemap(op);
	MouseButtonBindingMap::iterator b = bbm.find (bb);

	if (b != bbm.end()) {
		bbm.erase (b);
	}
}

void
Bindings::save (XMLNode& root)
{
	XMLNode* presses = new XMLNode (X_("Press"));

	for (KeybindingMap::iterator k = press_bindings.begin(); k != press_bindings.end(); ++k) {
		XMLNode* child;

		if (k->first.name().empty()) {
			continue;
		}

		child = new XMLNode (X_("Binding"));
		child->set_property (X_("key"), k->first.name());
		child->set_property (X_("action"), k->second.action_name);
		presses->add_child_nocopy (*child);
	}

	for (MouseButtonBindingMap::iterator k = button_press_bindings.begin(); k != button_press_bindings.end(); ++k) {
		XMLNode* child;
		child = new XMLNode (X_("Binding"));
		child->set_property (X_("button"), k->first.name());
		child->set_property (X_("action"), k->second.action_name);
		presses->add_child_nocopy (*child);
	}

	XMLNode* releases = new XMLNode (X_("Release"));

	for (KeybindingMap::iterator k = release_bindings.begin(); k != release_bindings.end(); ++k) {
		XMLNode* child;

		if (k->first.name().empty()) {
			continue;
		}

		child = new XMLNode (X_("Binding"));
		child->set_property (X_("key"), k->first.name());
		child->set_property (X_("action"), k->second.action_name);
		releases->add_child_nocopy (*child);
	}

	for (MouseButtonBindingMap::iterator k = button_release_bindings.begin(); k != button_release_bindings.end(); ++k) {
		XMLNode* child;
		child = new XMLNode (X_("Binding"));
		child->set_property (X_("button"), k->first.name());
		child->set_property (X_("action"), k->second.action_name);
		releases->add_child_nocopy (*child);
	}

	root.add_child_nocopy (*presses);
	root.add_child_nocopy (*releases);
}

void
Bindings::save_all_bindings_as_html (ostream& ostr)
{
	if (bindings.empty()) {
		return;
	}


	ostr << "<html>\n<head>\n<title>";
	ostr << PROGRAM_NAME;
	ostr << "</title>\n";
	ostr << "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />\n";

	ostr << "</head>\n<body>\n";

	ostr << "<table border=\"2\" cellpadding=\"6\"><tbody>\n\n";
	ostr << "<tr>\n\n";

	/* first column: separate by group */
	ostr << "<td>\n\n";
	for (list<Bindings*>::const_iterator b = bindings.begin(); b != bindings.end(); ++b) {
		(*b)->save_as_html (ostr, true);
	}
	ostr << "</td>\n\n";

	//second column
	ostr << "<td style=\"vertical-align:top\">\n\n";
	for (list<Bindings*>::const_iterator b = bindings.begin(); b != bindings.end(); ++b) {
		(*b)->save_as_html (ostr, false);
	}
	ostr << "</td>\n\n";


	ostr << "</tr>\n\n";
	ostr << "</tbody></table>\n\n";

	ostr << "</br></br>\n\n";
	ostr << "<table border=\"2\" cellpadding=\"6\"><tbody>\n\n";
	ostr << "<tr>\n\n";
	ostr << "<td>\n\n";
	ostr << "<h2><u> Partial List of Available Actions { => with current shortcut, where applicable } </u></h2>\n\n";
	{
		vector<string> paths;
		vector<string> labels;
		vector<string> tooltips;
		vector<string> keys;
		vector<Glib::RefPtr<Gtk::Action> > actions;

		ActionManager::get_all_actions (paths, labels, tooltips, keys, actions);

		vector<string>::iterator k;
		vector<string>::iterator p;
		vector<string>::iterator l;

		for (p = paths.begin(), k = keys.begin(), l = labels.begin(); p != paths.end(); ++k, ++p, ++l) {

			if ((*k).empty()) {
				ostr << *p  << " ( " << *l << " ) "  << "</br>" << endl;
			} else {
				ostr << *p << " ( " << *l << " ) " << " => " << *k << "</br>" << endl;
			}
		}
	}
	ostr << "</td>\n\n";
	ostr << "</tr>\n\n";
	ostr << "</tbody></table>\n\n";

	ostr << "</body>\n";
	ostr << "</html>\n";
}

void
Bindings::save_as_html (ostream& ostr, bool categorize) const
{

	if (!press_bindings.empty()) {

		ostr << "<h2><u>";
		if (categorize)
			ostr << _("Window") << ": " << name() << _(" (Categorized)");
		else
			ostr << _("Window") << ": " << name() << _(" (Alphabetical)");
		ostr << "</u></h2>\n\n";

		typedef std::map<std::string, std::vector<KeybindingMap::const_iterator> > GroupMap;
		GroupMap group_map;

		for (KeybindingMap::const_iterator k = press_bindings.begin(); k != press_bindings.end(); ++k) {

			if (k->first.name().empty()) {
				continue;
			}

			string group_name;
			if (categorize && !k->second.group_name.empty()) {
				group_name = k->second.group_name;
			} else {
				group_name = _("Uncategorized");
			}

			GroupMap::iterator gm = group_map.find (group_name);
			if (gm == group_map.end()) {
				std::vector<KeybindingMap::const_iterator> li;
				li.push_back (k);
				group_map.insert (make_pair (group_name,li));
			} else {
				gm->second.push_back (k);
			}
		}


		for (GroupMap::const_iterator gm = group_map.begin(); gm != group_map.end(); ++gm) {

			if (categorize) {
				ostr << "<h3>" << gm->first << "</h3>\n";
			}

			for (vector<KeybindingMap::const_iterator>::const_iterator k = gm->second.begin(); k != gm->second.end(); ++k) {

				if ((*k)->first.name().empty()) {
					continue;
				}

				RefPtr<Action> action;

				if ((*k)->second.action) {
					action = (*k)->second.action;
				} else {
					action = ActionManager::get_action ((*k)->second.action_name, false);
				}

				if (!action) {
					continue;
				}

				string key_name = (*k)->first.native_short_name ();
				replace_all (key_name, X_("KP_"), X_("Numpad "));
				replace_all (key_name, X_("nabla"), X_("Tab"));

				string::size_type pos;

				char const *targets[] = { X_("Separator"),  X_("Add"),        X_("Subtract"),    X_("Decimal"),      X_("Divide"),
				                          X_("grave"),      X_("comma"),      X_("period"),      X_("asterisk"),     X_("backslash"),
				                          X_("apostrophe"), X_("minus"),      X_("plus"),        X_("slash"),        X_("semicolon"),
				                          X_("colon"),      X_("equal"),      X_("bracketleft"), X_("bracketright"),
				                          X_("ampersand"),  X_("numbersign"), X_("parenleft"),   X_("parenright"),
				                          X_("quoteright"), X_("quoteleft"),  X_("exclam"),      X_("quotedbl"),
				                          X_("braceleft"),  X_("braceright"),
				                          0
				};

				char const *replacements[] = { X_("-"), X_("+"), X_("-"), X_("."), X_("/"),
				                               X_("`"), X_(","), X_("."), X_("*"), X_("\\"),
				                               X_("'"), X_("-"), X_("+"), X_("/"), X_(";"),
				                               X_(":"), X_("="), X_("["), X_("]"),
				                               X_("&"), X_("#"), X_("("), X_(")"),
				                               X_("`"), X_("'"), X_("!"), X_("\""),
				                               X_("{"), X_("}"),
				                               0
				};

				for (size_t n = 0; targets[n]; ++n) {
					if ((pos = key_name.find (targets[n])) != string::npos) {
						key_name.replace (pos, strlen (targets[n]), replacements[n]);
					}
				}

				key_name.append(" ");

				while (key_name.length()<28)
					key_name.append("-");

				ostr << "<span style=\"font-family:monospace;\">" << key_name;
				ostr << "<i>" << action->get_label() << "</i></span></br>\n";
			}
			ostr << "\n\n";

		}

		ostr << "\n";
	}
}

bool
Bindings::load (XMLNode const& node)
{
	const XMLNodeList& children (node.children());

	press_bindings.clear ();
	release_bindings.clear ();

	for (XMLNodeList::const_iterator i = children.begin(); i != children.end(); ++i) {
		/* each node could be Press or Release */
		load_operation (**i);
	}

	return true;
}

void
Bindings::load_operation (XMLNode const& node)
{
	if (node.name() == X_("Press") || node.name() == X_("Release")) {

		Operation op;

		if (node.name() == X_("Press")) {
			op = Press;
		} else {
			op = Release;
		}

		const XMLNodeList& children (node.children());

		for (XMLNodeList::const_iterator p = children.begin(); p != children.end(); ++p) {

			XMLProperty const * ap;
			XMLProperty const * kp;
			XMLProperty const * bp;
			XMLProperty const * gp;
			XMLNode const * child = *p;

			ap = child->property ("action");
			kp = child->property ("key");
			bp = child->property ("button");
			gp = child->property ("group");

			if (!ap || (!kp && !bp)) {
				continue;
			}

			if (kp) {
				KeyboardKey k;
				if (!KeyboardKey::make_key (kp->value(), k)) {
					continue;
				}
				add (k, op, ap->value(), gp);
			} else {
				MouseButton b;
				if (!MouseButton::make_button (bp->value(), b)) {
					continue;
				}
				add (b, op, ap->value(), gp);
			}
		}
	}
}

void
Bindings::get_all_actions (std::vector<std::string>& paths,
                           std::vector<std::string>& labels,
                           std::vector<std::string>& tooltips,
                           std::vector<std::string>& keys,
                           std::vector<RefPtr<Action> >& actions)
{
	/* build a reverse map from actions to bindings */

	typedef map<Glib::RefPtr<Gtk::Action>,KeyboardKey> ReverseMap;
	ReverseMap rmap;

	for (KeybindingMap::const_iterator k = press_bindings.begin(); k != press_bindings.end(); ++k) {
		rmap.insert (make_pair (k->second.action, k->first));
	}

	/* get a list of all actions XXX relevant for these bindings */

	std::vector<Glib::RefPtr<Action> > relevant_actions;
	ActionManager::get_actions (this, relevant_actions);

	for (vector<Glib::RefPtr<Action> >::const_iterator act = relevant_actions.begin(); act != relevant_actions.end(); ++act) {

		paths.push_back ((*act)->get_accel_path());
		labels.push_back ((*act)->get_label());
		tooltips.push_back ((*act)->get_tooltip());

		ReverseMap::iterator r = rmap.find (*act);

		if (r != rmap.end()) {
			keys.push_back (r->second.display_label());
		} else {
			keys.push_back (string());
		}

		actions.push_back (*act);
	}
}

Bindings*
Bindings::get_bindings (string const& name)
{
	for (list<Bindings*>::iterator b = bindings.begin(); b != bindings.end(); b++) {
		if ((*b)->name() == name) {
			return *b;
		}
	}

	return 0;
}

void
Bindings::associate_all ()
{
	for (list<Bindings*>::iterator b = bindings.begin(); b != bindings.end(); b++) {
		(*b)->associate ();
	}
}

bool
Bindings::is_bound (KeyboardKey const& kb, Operation op, std::string* path) const
{
	const KeybindingMap& km = get_keymap(op);
	KeybindingMap::const_iterator i = km.find (kb);
	if (i != km.end()) {
		if (path) {
			*path = i->second.action_name;
		}
		return true;
	}
	return false;
}

std::string
Bindings::bound_name (KeyboardKey const& kb, Operation op) const
{
	const KeybindingMap& km = get_keymap(op);
	KeybindingMap::const_iterator b = km.find(kb);

	if (b == km.end()) {
		return string();
	}

	if (!b->second.action) {
		/* action is looked up lazily, so it may not have been set yet */
		b->second.action = ActionManager::get_action (b->second.action_name, false);
	}

	return b->second.action->get_label ();
}

bool
Bindings::is_registered (Operation op, std::string const& action_name) const
{
	const KeybindingMap& km = get_keymap(op);
	return std::find_if(km.begin(),  km.end(),  ActionNameRegistered<KeybindingMap::const_iterator::value_type>(action_name)) != km.end();
}

Bindings::KeybindingMap&
Bindings::get_keymap (Operation op)
{
	switch (op) {
	case Press:
		return press_bindings;
	case Release:
	default:
		return release_bindings;
	}
}

const Bindings::KeybindingMap&
Bindings::get_keymap (Operation op) const
{
	switch (op) {
	case Press:
		return press_bindings;
	case Release:
	default:
		return release_bindings;
	}
}

Bindings::MouseButtonBindingMap&
Bindings::get_mousemap (Operation op)
{
	switch (op) {
	case Press:
		return button_press_bindings;
	case Release:
	default:
		return button_release_bindings;
	}
}

std::ostream& operator<<(std::ostream& out, Gtkmm2ext::KeyboardKey const & k) {
	char const *gdk_name = gdk_keyval_name (k.key());
	return out << "Key " << k.key() << " (" << (gdk_name ? gdk_name : "no-key") << ") state "
	           << hex << k.state() << dec << ' ' << show_gdk_event_state (k.state());
}

static void
delete_binding_set (void* p)
{
	delete (BindingSet*) p;
}

void
Gtkmm2ext::set_widget_bindings (Gtk::Widget& w, Bindings& b, char const * const name)
{
	BindingSet* bs = new BindingSet;
	bs->push_back (&b);
	g_object_set_data_full (G_OBJECT(w.gobj()), name, bs, (GDestroyNotify) delete_binding_set);
}

void
Gtkmm2ext::set_widget_bindings (Gtk::Widget& w, BindingSet& bs, char const * const name)
{
	w.set_data (name, &bs);
}


