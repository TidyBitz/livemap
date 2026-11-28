// SPDX-License-Identifier: GPL-3.0-or-later
import QtCore

/* The other end of the hover handshake: reads focus.ini without a process. A fresh Settings object re-reads the
 * file when its timestamp changed (QSettings checks), so one is made per read and dropped; the widget's `cat`
 * that did this before was a fork of plasmashell for every change. */
Settings {
    property string hover: ""
}
