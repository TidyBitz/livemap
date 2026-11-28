/*
 * Watches focus.ini in the data folder without a process: Qt's FolderListModel keeps a file-system watcher on
 * the folder and updates the file's modification time when the widget replaces the file. The FocusLayer reads
 * the file (one `cat`) only when this says it changed, instead of every 400 ms - so an idle desktop spawns
 * nothing at all. Loaded through a Loader so that a system without Qt.labs.folderlistmodel keeps the polling.
 */
import QtQuick
import Qt.labs.folderlistmodel

Item {
    id: watch
    property string folder: ""                    // the data folder as a file:// URL
    signal changed()
    FolderListModel {
        id: files
        folder: watch.folder
        nameFilters: ["focus.ini"]
        showDirs: false
        showOnlyReadable: true
    }
    Instantiator {
        model: files
        delegate: QtObject {
            required property date fileModified
            required property int fileSize
            onFileModifiedChanged: watch.changed()
            onFileSizeChanged: watch.changed()
            Component.onCompleted: watch.changed()
        }
    }
}
