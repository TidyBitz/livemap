// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import org.kde.plasma.plasma5support as P5Support

/* Runs shell commands through Plasma's executable engine - one short-lived DataSource per run - in place of one
 * long-lived P5Support.DataSource. The long-lived one leaks: every connectSource() adds a property for that
 * command string to the DataSource's data map for good (QQmlPropertyMap cannot drop a property), and the map's
 * dynamic meta-object is rebuilt, at a cost growing with the count, on every add and on every removal when the
 * engine drops an unused source. With a poll every 20 s and a different string each time, after a day or two
 * plasmashell's main thread spends itself rebuilding meta-objects with thousands of entries (the recurring
 * "CPU climbs back" of 0.47 and 0.48; three stacks sampled with gdb all sat in
 * Plasma5Support::DataSource::removeSource -> QQmlPropertyMap::clear -> QMetaObjectBuilder::toMetaObject).
 * Here each run has a DataSource of its own with one property, destroyed when its output arrives.
 * Same surface as before: connectSource(cmd), newData(source, data), disconnectSource(source) (a no-op). */
Item {
    id: runner
    visible: false                 // nothing to draw; invisible so a layout it sits in gives it no row
    width: 0; height: 0
    signal newData(string source, var data)
    property int running: 0
    function connectSource(cmd) {
        var ds = one.createObject(runner);
        if (!ds) return;
        running += 1;
        ds.connectSource(cmd);
    }
    function disconnectSource(source) { }
    Component {
        id: one
        P5Support.DataSource {
            engine: "executable"
            connectedSources: []
            onNewData: (source, data) => {
                disconnectSource(source);
                runner.running = Math.max(0, runner.running - 1);
                runner.newData(source, data);
                destroy();
            }
        }
    }
}
