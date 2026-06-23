import QtQuick
import Components

FocusScope {
    id: mixRoot

    signal goBack()

    property var navParams: ({})
    property string moduleId: "com.240mp.youtube_playlist"
    property var _moduleInfo: appCore.get_module_info(moduleId)
    property string moduleName: _moduleInfo.name || "VIDEO MIX"
    property string moduleIcon: _moduleInfo.icon || ""

    property string mode: "loading"
    property string statusText: "LOADING PLAYLIST..."
    property string playlistTitle: "YOUTUBE PLAYLIST"
    property string playlistInput: ""
    property var videos: []
    property int currentIndex: 0
    property bool loadingPlaylist: false
    property bool stoppingPlayback: false

    focus: true

    function settingValue(key, fallback) {
        var value = appCore.get_setting(moduleId, key)
        if (value === undefined || value === null || value === "") return fallback
        return value
    }

    function autoplayNext() {
        var value = settingValue("autoplay_next", true)
        return value === true || value === "ON" || value === "true"
    }

    function playbackQuality() {
        return settingValue("playback_quality", "360p")
    }

    function showSetup(message) {
        mode = "setup"
        statusText = message || "ENTER PLAYLIST CODE"
        playlistField.text = playlistInput || ""
        setupFocusTimer.restart()
    }

    function loadSavedPlaylist() {
        playlistInput = youtubePlaylistBackend.get_saved_playlist_input()
        if ((playlistInput || "").trim() === "") {
            showSetup("ENTER PLAYLIST CODE")
            return
        }
        loadPlaylist(playlistInput)
    }

    function loadPlaylist(input) {
        if (loadingPlaylist) return
        loadingPlaylist = true
        mode = "loading"
        statusText = "READING PLAYLIST..."
        youtubePlaylistBackend.load_playlist(input)
    }

    function savePlaylist() {
        var value = (playlistField.text || "").trim()
        if (value === "") {
            statusText = "ENTER PLAYLIST CODE"
            playlistField.forceActiveFocus()
            return
        }
        playlistInput = value
        appCore.save_setting(moduleId, "playlist_input", value)
        loadPlaylist(value)
    }

    function playIndex(index) {
        if (index < 0 || index >= videos.length) return
        currentIndex = index
        videoList.currentIndex = index
        var item = videos[index] || ({})
        var title = item.title || "VIDEO"
        statusText = "LOADING " + title
        mode = "playing"
        stoppingPlayback = false
        var format = youtubePlaylistBackend.ytdl_format_for_quality(playbackQuality())
        mpvController.loadAndPlay(item.url || "", 0.0, 0, -1, [], false, -1, 0.0,
                                  "", false, "", false, title, false, true, format)
    }

    function returnToList() {
        mode = videos.length > 0 ? "list" : "message"
        if (videos.length > 0)
            videoList.currentIndex = currentIndex
    }

    Keys.onPressed: function(event) {
        if (mode === "setup") {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                goBack()
                event.accepted = true
            }
            return
        }

        if (mode === "list") {
            if (event.key === Qt.Key_Up) {
                videoList.currentIndex = Math.max(0, videoList.currentIndex - 1)
                currentIndex = videoList.currentIndex
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                videoList.currentIndex = Math.min(videoList.count - 1, videoList.currentIndex + 1)
                currentIndex = videoList.currentIndex
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                playIndex(videoList.currentIndex)
                event.accepted = true
            } else if (event.key === Qt.Key_Menu) {
                showSetup("EDIT PLAYLIST CODE")
                event.accepted = true
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                goBack()
                event.accepted = true
            }
            return
        }

        if (mode === "playing") {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                stoppingPlayback = true
                mpvController.stop()
                returnToList()
                event.accepted = true
            } else if (event.key === Qt.Key_Menu) {
                mpvController.sendKey("MENU")
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                mpvController.sendKey("LEFT")
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                mpvController.sendKey("RIGHT")
                event.accepted = true
            } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                mpvController.sendKey("SPACE")
                event.accepted = true
            }
            return
        }

        if (mode === "message") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                loadSavedPlaylist()
                event.accepted = true
            } else if (event.key === Qt.Key_Menu) {
                showSetup("EDIT PLAYLIST CODE")
                event.accepted = true
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                goBack()
                event.accepted = true
            }
        }
    }

    Component.onCompleted: loadSavedPlaylist()

    Component.onDestruction: {
        if (mpvController.running)
            mpvController.stop()
    }

    Timer {
        id: setupFocusTimer
        interval: 1
        repeat: false
        onTriggered: {
            playlistField.forceActiveFocus()
            playlistField.selectAll()
        }
    }

    Connections {
        target: youtubePlaylistBackend

        function onPlaylistLoaded(title, items) {
            loadingPlaylist = false
            playlistTitle = title || "YOUTUBE PLAYLIST"
            videos = items || []
            if (videos.length === 0) {
                mode = "message"
                statusText = "PLAYLIST HAS NO VIDEOS"
                return
            }
            mode = "list"
            currentIndex = Math.min(currentIndex, videos.length - 1)
            videoList.currentIndex = currentIndex
        }

        function onErrorOccurred(message) {
            loadingPlaylist = false
            mode = (playlistInput || "").trim() === "" ? "setup" : "message"
            statusText = message || "YOUTUBE PLAYLIST FAILED"
            if (mode === "setup")
                setupFocusTimer.restart()
        }
    }

    Connections {
        target: mpvController

        function onPlaybackFinishedNaturally(finalPositionMs, finalDurationMs) {
            if (mode !== "playing") return
            if (autoplayNext() && currentIndex + 1 < videos.length) {
                playIndex(currentIndex + 1)
                return
            }
            returnToList()
        }

        function onPlaybackFinished(finalPositionMs, finalDurationMs) {
            if (stoppingPlayback) {
                stoppingPlayback = false
                return
            }
            if (mode === "playing")
                returnToList()
        }

        function onPlaybackFailed() {
            mode = "message"
            statusText = "YOUTUBE PLAYBACK FAILED"
        }
    }

    StaticBackground {
        anchors.fill: parent
        visible: root.staticBackgroundEnabled && mode !== "playing"
        running: visible
    }

    Rectangle {
        anchors.fill: parent
        color: root.staticBackgroundEnabled && mode !== "playing" ? "transparent" : root.surfaceColor
    }

    AppBar {
        iconSource: moduleIcon
        title: moduleName
        subtitle: mode === "list" ? playlistTitle : "PLAYLIST"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125
        anchors.leftMargin: root.sw * 0.125
    }

    Text {
        visible: mode === "loading" || mode === "message" || mode === "playing"
        text: mode === "playing" ? statusText : statusText
        color: root.primaryColor
        font.family: root.globalFont
        font.capitalization: Font.AllUppercase
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        width: root.sw * 0.78
        wrapMode: Text.WordWrap
        font.pixelSize: root.sh * 0.045
    }

    Column {
        visible: mode === "setup"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.sw * 0.115625
        anchors.rightMargin: root.sw * 0.115625
        spacing: root.sh * 0.025

        Text {
            text: statusText
            color: root.secondaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: root.sh * 0.0333333
        }

        Rectangle {
            width: parent.width
            height: root.sh * 0.075
            color: root.accentColor

            TextInput {
                id: playlistField
                anchors.fill: parent
                anchors.leftMargin: root.sw * 0.009375
                anchors.rightMargin: root.sw * 0.009375
                verticalAlignment: TextInput.AlignVCenter
                color: root.surfaceColor
                selectedTextColor: root.surfaceColor
                selectionColor: root.tertiaryColor
                font.family: root.globalFont
                font.pixelSize: root.sh * 0.045
                clip: true

                Keys.onReturnPressed: mixRoot.savePlaylist()
                Keys.onEnterPressed: mixRoot.savePlaylist()
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Back) {
                        mixRoot.goBack()
                        event.accepted = true
                    }
                }
            }
        }

        Text {
            text: "PASTE URL OR JUST THE LIST CODE"
            color: root.tertiaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: root.sh * 0.03
        }
    }

    ListView {
        id: videoList
        visible: mode === "list"
        model: videos
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.25
        anchors.leftMargin: root.sw * 0.115625
        width: root.sw * 0.76875
        height: root.sh * 0.525
        clip: true
        focus: visible

        delegate: Item {
            width: videoList.width
            height: root.sh * 0.0583333

            Rectangle {
                anchors.fill: videoText
                color: root.accentColor
                visible: videoList.currentIndex === index
            }

            Text {
                id: videoText
                text: (index + 1 < 10 ? "0" : "") + (index + 1) + "  " + (modelData.title || "VIDEO")
                color: videoList.currentIndex === index ? root.surfaceColor : root.primaryColor
                font.family: root.globalFont
                font.capitalization: Font.AllUppercase
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                elide: Text.ElideRight
                leftPadding: root.sw * 0.009375
                rightPadding: root.sw * 0.009375
                font.pixelSize: root.sh * 0.05
            }
        }
    }
}
