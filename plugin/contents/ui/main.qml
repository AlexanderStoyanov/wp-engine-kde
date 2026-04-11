import QtQuick
import QtQuick.Window
import QtMultimedia
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

WallpaperItem {
    id: root

    readonly property string wpSource: root.configuration.WallpaperSource || ""
    readonly property string wpType: root.configuration.WallpaperType || ""
    readonly property string wpWorkshopId: root.configuration.WallpaperWorkShopId || ""
    readonly property int fillMode: root.configuration.FillMode || 0
    readonly property bool muted: root.configuration.MuteAudio
    readonly property int vol: root.configuration.Volume || 100
    readonly property real speed: root.configuration.Speed || 1.0
    readonly property int sceneFps: root.configuration.SceneFps ?? 60
    readonly property string lweBinary: root.configuration.LweBinaryPath || ""

    readonly property string steamLibrary: root.configuration.SteamLibraryPath || ""
    readonly property string assetsDir: {
        if (steamLibrary === "") return ""
        return steamLibrary + "/steamapps/common/wallpaper_engine/assets"
    }

    readonly property string sceneManagerPath: {
        var url = Qt.resolvedUrl("../scripts/scene_manager.sh").toString()
        if (url.startsWith("file://"))
            return url.substring(7)
        return url
    }

    // Screen.name gives the display output name (e.g. "DP-1", "HDMI-A-1")
    // used to scope the scene renderer to this specific screen.
    readonly property string screenName: Screen.name || ""

    property bool sceneRunning: false
    property string sceneError: ""
    property string activeSceneId: ""

    onWpSourceChanged: loadWallpaper()
    onWpTypeChanged: loadWallpaper()
    onWpWorkshopIdChanged: loadWallpaper()
    onScreenNameChanged: {
        if (screenName !== "" && wpType === "scene" && !sceneRunning)
            loadWallpaper()
    }

    P5Support.DataSource {
        id: sceneExec
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            var stdout = data["stdout"] || ""
            try {
                var result = JSON.parse(stdout)
                if (result.status === "running") {
                    root.sceneRunning = true
                    root.sceneError = ""
                } else if (result.status === "error") {
                    root.sceneRunning = false
                    root.sceneError = result.message || "Unknown error"
                } else {
                    root.sceneRunning = false
                    root.sceneError = ""
                }
            } catch (e) {
                root.sceneRunning = false
                root.sceneError = "Scene manager returned invalid response"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.sceneRunning ? "transparent" : "black"
    }

    MediaPlayer {
        id: mediaPlayer
        loops: MediaPlayer.Infinite
        videoOutput: videoOutput
        audioOutput: audioOutput
        playbackRate: root.speed

        onErrorOccurred: function(error, errorString) {
            errorLabel.text = errorString
            errorLabel.visible = true
        }
    }

    AudioOutput {
        id: audioOutput
        muted: root.muted
        volume: root.vol / 100.0
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: {
            switch (root.fillMode) {
            case 0: return VideoOutput.PreserveAspectCrop
            case 1: return VideoOutput.Stretch
            case 2: return VideoOutput.PreserveAspectFit
            default: return VideoOutput.PreserveAspectCrop
            }
        }
    }

    Text {
        id: errorLabel
        anchors.centerIn: parent
        color: "#ee4444"
        font.pointSize: 12
        visible: false
        wrapMode: Text.WordWrap
        width: parent.width * 0.8
        horizontalAlignment: Text.AlignHCenter
    }

    Text {
        id: placeholderLabel
        anchors.centerIn: parent
        color: "#666666"
        font.pointSize: 14
        visible: root.wpSource === "" && !errorLabel.visible && !root.sceneRunning
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 1.5
        text: "No wallpaper selected.\nRight-click desktop → Configure Desktop and Wallpaper"
    }

    Text {
        id: sceneActiveLabel
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 8
        color: "#44ffffff"
        font.pointSize: 8
        visible: root.sceneRunning
        text: "Scene: " + screenName
    }

    function startScene() {
        if (wpWorkshopId === "" || assetsDir === "") return

        var sceneKey = wpWorkshopId + ":" + screenName + ":" + sceneFps
        if (sceneRunning && activeSceneId === sceneKey) return

        var screen = screenName
        if (screen === "") {
            console.warn("wp-engine-kde: could not determine screen name, scene may not render correctly")
            screen = "unknown"
        }

        activeSceneId = sceneKey
        var lweArg = lweBinary !== "" ? (' "' + lweBinary + '"') : ""
        var cmd = 'bash "' + sceneManagerPath + '" start "' + wpWorkshopId + '" "' + assetsDir + '" ' + sceneFps + ' "' + screen + '"' + lweArg
        sceneExec.connectSource(cmd)
    }

    function stopScene() {
        var screen = screenName
        var screenArg = screen !== "" ? (' "' + screen + '"') : ""
        var cmd = 'bash "' + sceneManagerPath + '" stop' + screenArg
        sceneExec.connectSource(cmd)
        sceneRunning = false
        activeSceneId = ""
    }

    function loadWallpaper() {
        mediaPlayer.stop()
        mediaPlayer.source = ""
        errorLabel.visible = false
        sceneError = ""

        if (wpSource === "" && wpWorkshopId === "") {
            stopScene()
            return
        }

        if (wpType === "video") {
            stopScene()
            mediaPlayer.source = Qt.url("file://" + wpSource)
            mediaPlayer.play()
        } else if (wpType === "scene") {
            startScene()
        } else if (wpType !== "") {
            stopScene()
            errorLabel.text = "Wallpaper type '" + wpType + "' is not yet supported."
            errorLabel.visible = true
        }
    }

    onSceneErrorChanged: {
        if (sceneError !== "") {
            errorLabel.text = sceneError
            errorLabel.visible = true
        }
    }

    Component.onCompleted: loadWallpaper()
    Component.onDestruction: stopScene()
}
