import QtQuick
import QtMultimedia
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    readonly property string wpSource: root.configuration.WallpaperSource || ""
    readonly property string wpType: root.configuration.WallpaperType || ""
    readonly property int fillMode: root.configuration.FillMode || 0
    readonly property bool muted: root.configuration.MuteAudio
    readonly property int vol: root.configuration.Volume || 100
    readonly property double speed: root.configuration.Speed || 1.0

    onWpSourceChanged: loadWallpaper()
    onWpTypeChanged: loadWallpaper()

    Rectangle {
        anchors.fill: parent
        color: "black"
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
        visible: root.wpSource === "" && !errorLabel.visible
        horizontalAlignment: Text.AlignHCenter
        lineHeight: 1.5
        text: "No wallpaper selected.\nRight-click desktop \u2192 Configure Desktop and Wallpaper"
    }

    function loadWallpaper() {
        mediaPlayer.stop()
        errorLabel.visible = false

        if (wpSource === "") {
            mediaPlayer.source = ""
            return
        }

        if (wpType === "video") {
            mediaPlayer.source = Qt.url("file://" + wpSource)
            mediaPlayer.play()
        } else if (wpType !== "") {
            mediaPlayer.source = ""
            errorLabel.text = "Wallpaper type '" + wpType + "' is not yet supported.\nOnly video wallpapers work in this version."
            errorLabel.visible = true
        }
    }

    Component.onCompleted: loadWallpaper()
}
