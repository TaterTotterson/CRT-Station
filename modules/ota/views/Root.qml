import QtQuick
import Components

FocusScope {
    id: otaRoot

    signal goBack()

    property var navParams: ({})
    property string moduleId: "com.240mp.ota"
    property var _moduleInfo: appCore.get_module_info(moduleId)
    property string moduleName: _moduleInfo.name || "OVER THE AIR"
    property string moduleIcon: _moduleInfo.icon || ""

    property var channels: []
    property int currentIndex: -1
    property string pendingChannelId: ""
    property string statusText: "LOADING CHANNELS..."
    property string serverName: ""
    property bool leaving: false
    property bool hasStartedPlayback: false
    property bool tuningStaticVisible: true
    property bool stoppingForTune: false
    property bool streamRequestActive: false
    property int tuneDelayMs: 1200

    focus: true

    function newSessionId() {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var id = ""
        for (var i = 0; i < 12; i++) id += chars[Math.floor(Math.random() * chars.length)]
        return id
    }

    function channelLabel(channel) {
        if (!channel) return "NO CHANNEL"
        var number = channel.number || ""
        var name = channel.name || ""
        if (number !== "" && name !== "") return "CH " + number + "  " + name
        if (number !== "") return "CH " + number
        if (name !== "") return name
        return "CHANNEL"
    }

    function selectedChannel() {
        if (currentIndex < 0 || currentIndex >= channels.length) return null
        return channels[currentIndex]
    }

    function showStaticForChannel(channel) {
        if (!channel || !channel.id) return

        tuningStaticVisible = true
        hasStartedPlayback = false
        streamRequestActive = false
        statusText = channelLabel(channel)
        pendingChannelId = channel.id

        if (mpvController.running) {
            stoppingForTune = true
            mpvController.stop()
        }
    }

    function requestSelectedStream() {
        var channel = selectedChannel()
        if (!channel || !channel.id) return

        tuneTimer.stop()
        pendingChannelId = channel.id
        streamRequestActive = true
        statusText = "TUNING " + channelLabel(channel)
        appCore.save_setting(moduleId, "last_channel_id", channel.id)
        embyBackend.request_live_tv_stream(channel.id, newSessionId(), false)
    }

    function tuneIndex(index, immediate) {
        if (channels.length === 0) return
        if (index < 0) index = channels.length - 1
        if (index >= channels.length) index = 0

        currentIndex = index
        var channel = channels[currentIndex]
        if (!channel || !channel.id) return

        showStaticForChannel(channel)
        if (immediate) {
            requestSelectedStream()
        } else {
            tuneTimer.restart()
        }
    }

    function tuneRelative(delta, immediate) {
        if (channels.length === 0) return
        tuneIndex(currentIndex + delta, !!immediate)
    }

    function tuneNow() {
        if (channels.length === 0) return
        if (tuningStaticVisible || tuneTimer.running || streamRequestActive)
            requestSelectedStream()
    }

    function exitOta() {
        leaving = true
        tuneTimer.stop()
        mpvController.stop()
        goBack()
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Up) {
            tuneRelative(1, false)
            event.accepted = true
        } else if (event.key === Qt.Key_Down) {
            tuneRelative(-1, false)
            event.accepted = true
        } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
            exitOta()
            event.accepted = true
        } else if (event.key === Qt.Key_Space) {
            mpvController.sendKey("SPACE")
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            mpvController.sendKey("LEFT")
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            mpvController.sendKey("RIGHT")
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            tuneNow()
            event.accepted = true
        }
    }

    Timer {
        id: tuneTimer
        interval: otaRoot.tuneDelayMs
        repeat: false
        onTriggered: otaRoot.requestSelectedStream()
    }

    Connections {
        target: embyBackend

        function onLiveTvChannelsLoaded(items) {
            channels = items || []
            if (channels.length === 0) {
                statusText = "NO OTA CHANNELS"
                return
            }

            var restoreId = appCore.get_setting(moduleId, "last_channel_id") || ""
            var restoreIndex = 0
            for (var i = 0; i < channels.length; i++) {
                if (channels[i].id === restoreId) {
                    restoreIndex = i
                    break
                }
            }
            tuneIndex(restoreIndex, false)
        }

        function onLiveTvStreamReady(channelId, url, httpHeaderFields) {
            if (channelId !== pendingChannelId) return

            var channel = channels[currentIndex]
            var label = channelLabel(channel)
            statusText = label
            hasStartedPlayback = true
            tuningStaticVisible = false
            streamRequestActive = false
            mpvController.loadAndPlay(url, 0.0, 0, -1, [], false, -1, 0.0,
                                      httpHeaderFields, false, "ota", false, label)
        }

        function onErrorOccurred(msg) {
            statusText = msg || "OTA ERROR"
            streamRequestActive = false
            tuningStaticVisible = true
        }
    }

    Connections {
        target: mpvController
        function onPlaybackFinished(finalPositionMs, finalDurationMs) {
            if (stoppingForTune) {
                stoppingForTune = false
                return
            }
            if (!leaving && hasStartedPlayback)
                goBack()
        }
        function onPlaybackFailed() {
            if (stoppingForTune) {
                stoppingForTune = false
                return
            }
            statusText = "OTA PLAYBACK FAILED"
            streamRequestActive = false
            tuningStaticVisible = true
        }
        function onScriptMessageReceived(message, arg) {
            if (message === "240mp-ota-tune-now") {
                tuneNow()
                return
            }

            if (message !== "240mp-ota-channel-step")
                return

            var delta = parseInt(arg)
            if (isNaN(delta) || delta === 0)
                return

            tuneRelative(delta, false)
        }
    }

    Component.onCompleted: {
        serverName = embyBackend.get_active_server_name()
        if (embyBackend.get_auth_state() !== "authed") {
            statusText = "SIGN IN TO VIDEO ON DEMAND"
            return
        }
        embyBackend.load_live_tv_channels()
    }

    Component.onDestruction: {
        if (!leaving)
            mpvController.stop()
    }

    StaticBackground {
        anchors.fill: parent
        visible: otaRoot.tuningStaticVisible
        running: visible
    }

    Rectangle {
        anchors.fill: parent
        color: otaRoot.tuningStaticVisible ? "transparent" : "black"
    }

    AppBar {
        iconSource: otaRoot.moduleIcon
        title: otaRoot.moduleName
        subtitle: otaRoot.serverName
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125
        anchors.leftMargin: root.sw * 0.125
        visible: otaRoot.tuningStaticVisible || !hasStartedPlayback
    }

    Text {
        text: statusText
        color: root.primaryColor
        font.family: root.globalFont
        font.capitalization: Font.AllUppercase
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        width: root.sw * 0.8
        wrapMode: Text.WordWrap
        font.pixelSize: root.sh * 0.05
        visible: otaRoot.tuningStaticVisible || !hasStartedPlayback
    }

    Text {
        text: root.hints.back + ":BACK  CH +/-:UP/DOWN  OK:TUNE"
        color: root.tertiaryColor
        font.family: root.globalFont
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: root.sh * 0.1041667
        anchors.leftMargin: root.sw * 0.125
        font.pixelSize: root.sh * 0.0333333
        visible: otaRoot.tuningStaticVisible || !hasStartedPlayback
    }
}
