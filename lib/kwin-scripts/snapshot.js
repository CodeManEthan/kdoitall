// kdoitall snapshot — atomic window state collector for KWin 6.
// Runs once when the script is started, builds a JSON snapshot of every
// window in workspace.windowList(), and delivers it via a single DBus
// method call to a receiver registered on the session bus.
//
// Pattern: bash side spawns the receiver before calling start(), so by the
// time the JS callDBus fires the receiver is already listening. There is no
// race window — we own both ends.

(function () {
    var payload;
    try {
        var windows = workspace.windowList();
        var out = [];
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i];
            var desktops = [];
            if (w.desktops) {
                for (var j = 0; j < w.desktops.length; j++) {
                    var d = w.desktops[j];
                    desktops.push({
                        id: d.id ? d.id.toString() : "",
                        x11Number: d.x11DesktopNumber
                    });
                }
            }
            out.push({
                internalId: w.internalId.toString(),
                resourceClass: w.resourceClass || "",
                resourceName: w.resourceName || "",
                desktopFileName: w.desktopFileName || "",
                caption: w.caption || "",
                desktops: desktops,
                onAllDesktops: !!w.onAllDesktops,
                frameGeometry: {
                    x: w.frameGeometry.x,
                    y: w.frameGeometry.y,
                    width: w.frameGeometry.width,
                    height: w.frameGeometry.height
                },
                output: (w.output && w.output.name) ? w.output.name : "",
                normalWindow: !!w.normalWindow,
                splash: !!w.splash,
                dock: !!w.dock,
                notification: !!w.notification,
                dialog: !!w.dialog,
                popupWindow: !!w.popupWindow,
                utility: !!w.utility,
                toolbar: !!w.toolbar,
                menu: !!w.menu,
                tooltip: !!w.tooltip,
                criticalNotification: !!w.criticalNotification,
                onScreenDisplay: !!w.onScreenDisplay,
                desktopWindow: !!w.desktopWindow,
                dndIcon: !!w.dndIcon
            });
        }
        payload = JSON.stringify({
            timestamp: new Date().getTime(),
            windowCount: out.length,
            windows: out
        });
    } catch (e) {
        payload = JSON.stringify({
            error: e && e.toString ? e.toString() : "unknown error",
            timestamp: new Date().getTime()
        });
    }

    callDBus(
        "org.kdoitall.Snapshot",
        "/Snapshot",
        "org.kdoitall.Snapshot",
        "Deliver",
        payload
    );
})();
