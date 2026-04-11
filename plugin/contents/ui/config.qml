import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

ColumnLayout {
    id: root

    property var configDialog
    property var wallpaperConfiguration: wallpaper.configuration

    property string cfg_SteamLibraryPath
    property string cfg_WallpaperWorkShopId
    property string cfg_WallpaperSource
    property string cfg_WallpaperType
    property bool cfg_MuteAudio
    property int cfg_Volume
    property int cfg_FillMode
    property int cfg_PauseMode
    property real cfg_Speed
    property int cfg_SceneFps
    property string cfg_LweBinaryPath

    readonly property string workshopPath: {
        if (!cfg_SteamLibraryPath || cfg_SteamLibraryPath === "")
            return ""
        return cfg_SteamLibraryPath + "/steamapps/workshop/content/431960"
    }

    readonly property string scriptPath: {
        var url = Qt.resolvedUrl("../scripts/scan_wallpapers.py").toString()
        if (url.startsWith("file://"))
            return url.substring(7)
        return url
    }

    property bool scanning: false
    property string filterType: "all"
    property string searchQuery: ""

    spacing: Kirigami.Units.smallSpacing

    ListModel { id: wallpaperModel }
    ListModel { id: filteredModel }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""
            var exitCode = data["exit code"]

            if (exitCode !== 0 || stdout.trim() === "") {
                console.warn("wp-engine-kde: scan failed:", stderr)
                root.scanning = false
                return
            }

            try {
                var wallpapers = JSON.parse(stdout)
                wallpaperModel.clear()
                for (var i = 0; i < wallpapers.length; i++) {
                    var wp = wallpapers[i]
                    wallpaperModel.append({
                        workshopId: wp.workshopId || "",
                        title: wp.title || "Untitled",
                        wpType: (wp.type || "unknown").toLowerCase(),
                        preview: "file://" + wp.dirPath + "/" + (wp.preview || "preview.jpg"),
                        filePath: wp.dirPath + "/" + (wp.file || ""),
                        description: wp.description || "",
                        tags: (wp.tags || []).join(", ")
                    })
                }
                applyFilter()
            } catch (e) {
                console.warn("wp-engine-kde: JSON parse error:", e)
            }
            root.scanning = false
        }
    }

    function applyFilter() {
        filteredModel.clear()
        var query = searchQuery.toLowerCase()
        for (var i = 0; i < wallpaperModel.count; i++) {
            var wp = wallpaperModel.get(i)
            if (filterType !== "all" && wp.wpType !== filterType)
                continue
            if (query !== "" && wp.title.toLowerCase().indexOf(query) === -1
                && wp.tags.toLowerCase().indexOf(query) === -1)
                continue
            filteredModel.append(wp)
        }
    }

    onFilterTypeChanged: applyFilter()
    onSearchQueryChanged: applyFilter()

    Timer {
        id: scanTimer
        interval: 200
        repeat: false
        onTriggered: doScan()
    }

    function scanWallpapers() { scanTimer.restart() }

    function doScan() {
        if (workshopPath === "") {
            wallpaperModel.clear()
            filteredModel.clear()
            scanning = false
            return
        }
        scanning = true
        var cmd = 'python3 "' + scriptPath + '" "' + workshopPath + '"'
        executable.connectSource(cmd)
    }

    Component.onCompleted: {
        if (workshopPath !== "")
            scanWallpapers()
    }

    onWorkshopPathChanged: {
        if (workshopPath !== "")
            scanWallpapers()
    }

    // --- Steam path + refresh ---
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            Layout.fillWidth: true
            text: cfg_SteamLibraryPath
            placeholderText: "Steam library path, e.g. /home/user/.local/share/Steam"
            onEditingFinished: cfg_SteamLibraryPath = text
        }

        QQC2.Button {
            icon.name: "view-refresh"
            onClicked: scanWallpapers()
        }
    }

    // --- Search + filter ---
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            Layout.fillWidth: true
            placeholderText: "Search wallpapers\u2026"
            onTextChanged: searchQuery = text
        }

        QQC2.ComboBox {
            model: ["All Types", "Video Only", "Scene Only"]
            onCurrentIndexChanged: {
                filterType = ["all", "video", "scene"][currentIndex]
            }
        }

        QQC2.Label {
            text: root.scanning ? "Scanning\u2026" : (filteredModel.count + " / " + wallpaperModel.count)
            opacity: 0.6
        }
    }

    // --- Wallpaper grid ---
    GridView {
        id: wallpaperGrid
        Layout.fillWidth: true
        Layout.fillHeight: true

        cellWidth: 196
        cellHeight: 136
        clip: true
        model: filteredModel

        delegate: Item {
            width: wallpaperGrid.cellWidth
            height: wallpaperGrid.cellHeight

            required property int index
            required property string workshopId
            required property string title
            required property string wpType
            required property string preview
            required property string filePath

            readonly property bool isCurrent: workshopId === cfg_WallpaperWorkShopId

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 4
                color: isCurrent ? Kirigami.Theme.highlightColor : "transparent"
                border.color: isCurrent ? Kirigami.Theme.highlightColor : Kirigami.Theme.backgroundColor
                border.width: 2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 3
                        clip: true
                        color: "#222222"

                        Image {
                            anchors.fill: parent
                            source: preview
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        // Type badge
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 3
                            width: badgeLabel.implicitWidth + 8
                            height: badgeLabel.implicitHeight + 4
                            radius: 3
                            color: wpType === "video" ? "#2e7d32" : "#f57f17"
                            opacity: 0.85

                            QQC2.Label {
                                id: badgeLabel
                                anchors.centerIn: parent
                                text: wpType === "video" ? "Video" : "Scene"
                                color: "white"
                                font.pointSize: 7
                                font.bold: true
                            }
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        Layout.leftMargin: 2
                        Layout.rightMargin: 2
                        text: title
                        elide: Text.ElideRight
                        font.bold: isCurrent
                        font.pointSize: 8
                        verticalAlignment: Text.AlignVCenter
                        color: isCurrent ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        cfg_WallpaperWorkShopId = workshopId
                        cfg_WallpaperSource = filePath
                        cfg_WallpaperType = wpType
                    }
                }
            }
        }
    }

    // --- Playback settings ---
    Kirigami.FormLayout {
        Layout.fillWidth: true

        QQC2.ComboBox {
            Kirigami.FormData.label: "Fill mode:"
            model: ["Scaled and cropped", "Stretched", "Fit (keep proportions)"]
            currentIndex: cfg_FillMode
            onActivated: (index) => { cfg_FillMode = index }
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: "Pause when:"
            model: ["Never pause", "Window maximized", "Window fullscreen"]
            currentIndex: cfg_PauseMode
            onActivated: (index) => { cfg_PauseMode = index }
        }

        RowLayout {
            Kirigami.FormData.label: "Audio:"
            QQC2.CheckBox {
                text: "Mute"
                checked: cfg_MuteAudio
                onToggled: cfg_MuteAudio = checked
            }
            QQC2.SpinBox {
                from: 0
                to: 100
                value: cfg_Volume
                enabled: !cfg_MuteAudio
                onValueModified: cfg_Volume = value
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Speed:"
            QQC2.SpinBox {
                from: 25
                to: 200
                stepSize: 25
                value: Math.round(cfg_Speed * 100)
                onValueModified: cfg_Speed = value / 100.0

                textFromValue: function(value) { return (value / 100.0).toFixed(2) + "x" }
                valueFromText: function(text) { return Math.round(parseFloat(text) * 100) }
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Scene FPS:"
            QQC2.SpinBox {
                from: 0
                to: 120
                stepSize: 5
                value: cfg_SceneFps
                onValueModified: cfg_SceneFps = value

                textFromValue: function(value) { return value === 0 ? "Unlimited" : value.toString() }
                valueFromText: function(text) { return text === "Unlimited" ? 0 : parseInt(text) || 30 }
            }
            QQC2.Label {
                text: "(0 = unlimited)"
                opacity: 0.6
            }
        }

        QQC2.TextField {
            Kirigami.FormData.label: "Scene renderer:"
            text: cfg_LweBinaryPath
            placeholderText: "Auto-detect (searches ~/.local/bin, /usr/bin, PATH)"
            onEditingFinished: cfg_LweBinaryPath = text
        }
    }
}
