// SPDX-License-Identifier: GPL-3.0-or-later
import QtCore

/* The hover handshake's file, written without a process. Qt's Settings keeps an ini file wherever `location`
 * points; one short-lived object per write: set `focus`, let it go, and its destructor flushes the file. A shell
 * `printf` did this before - a fork of plasmashell (13 GB of address space to map) on every row the pointer
 * crossed, which was the jitter over the Events list. */
Settings {
    property string hover: ""
}
