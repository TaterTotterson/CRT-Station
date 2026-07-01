import QtQuick
import Components

FocusScope {
    id: addRoot

    property var navParams: ({})

    signal goBack()

    property string youtubeModuleId: "com.240mp.youtube_playlist"
    property string statusText: "ADD COMMERCIAL PLAYLIST"
    property bool addingPlaylist: false
    property string pendingInput: ""

    focus: true

    function listSetting(key) {
        var value = appCore.get_setting(youtubeModuleId, key)
        return Array.isArray(value) ? value : []
    }

    function saveCommercialPlaylists(rows) {
        appCore.save_setting(youtubeModuleId, "commercial_playlists", rows)
    }

    function addPlaylist() {
        if (addingPlaylist)
            return

        var value = (playlistField.text || "").trim()
        playlistField.text = value
        if (value === "") {
            statusText = "ENTER PLAYLIST CODE"
            playlistField.forceActiveFocus()
            return
        }

        addingPlaylist = true
        pendingInput = value
        statusText = "READING PLAYLIST INFO..."
        lookupTimer.restart()
    }

    function finishAddPlaylist() {
        if (!addingPlaylist)
            return

        var value = pendingInput
        var info = youtubePlaylistBackend.resolve_playlist_info(value)
        addingPlaylist = false
        pendingInput = ""

        if (!info || info.ok !== true || !info.url) {
            statusText = (info && info.message) ? info.message : "PLAYLIST LOOKUP FAILED - TRY AGAIN"
            playlistField.text = value || playlistField.text
            playlistField.forceActiveFocus()
            playlistField.selectAll()
            return
        }

        var saved = listSetting("commercial_playlists")
        var next = []
        for (var i = 0; i < saved.length; i++) {
            var item = Object.assign({}, saved[i] || ({}))
            if ((item.url || "") === info.url) {
                statusText = "PLAYLIST ALREADY ADDED"
                backTimer.restart()
                return
            }
            next.push(item)
        }

        next.push({
            id: info.id || info.url,
            input: info.input || value,
            url: info.url,
            title: info.title || ("COMMERCIALS " + (next.length + 1))
        })
        saveCommercialPlaylists(next)
        statusText = "COMMERCIAL PLAYLIST ADDED"
        backTimer.restart()
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
            goBack()
            event.accepted = true
        }
    }

    Timer {
        id: focusTimer
        interval: 1
        repeat: false
        onTriggered: {
            playlistField.forceActiveFocus()
            playlistField.selectAll()
        }
    }

    Timer {
        id: lookupTimer
        interval: 50
        repeat: false
        onTriggered: addRoot.finishAddPlaylist()
    }

    Timer {
        id: backTimer
        interval: 650
        repeat: false
        onTriggered: addRoot.goBack()
    }

    Component.onCompleted: focusTimer.restart()

    StaticBackground {
        anchors.fill: parent
        visible: root.staticBackgroundEnabled
        running: visible
    }

    Rectangle {
        anchors.fill: parent
        color: root.staticBackgroundEnabled ? "transparent" : root.surfaceColor
    }

    AppBar {
        iconSource: moduleRoot.moduleIcon
        iconHeight: root.sh * 0.075
        title: moduleRoot.moduleName
        subtitle: "COMMERCIALS"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125
        anchors.leftMargin: root.sw * 0.125
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.sw * 0.115625
        anchors.rightMargin: root.sw * 0.115625
        spacing: root.sh * 0.025

        Text {
            text: addRoot.statusText
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

                Keys.onReturnPressed: function(event) {
                    addRoot.addPlaylist()
                    event.accepted = true
                }
                Keys.onEnterPressed: function(event) {
                    addRoot.addPlaylist()
                    event.accepted = true
                }
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                        addRoot.goBack()
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
}
