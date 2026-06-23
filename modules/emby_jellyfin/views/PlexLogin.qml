import QtQuick
import Components

FocusScope {
    id: plexRoot

    property var navParams: ({})

    signal replaceWith(string path, var params)
    signal goBack()

    property string code: ""
    property string linkUrl: "https://plex.tv/link"
    property string statusText: "REQUESTING PLEX CODE..."
    property string errorMessage: ""
    property var servers: []
    property int serverIndex: 0
    property bool waitingForApproval: false

    focus: true

    function begin() {
        code = ""
        servers = []
        errorMessage = ""
        waitingForApproval = true
        statusText = "REQUESTING PLEX CODE..."
        embyBackend.start_plex_pin_login()
    }

    function selectServer() {
        if (servers.length === 0) return
        var server = servers[serverIndex]
        if (!server || !server.machineIdentifier) return
        statusText = "CONNECTING TO " + (server.name || "PLEX")
        embyBackend.select_plex_server(server.machineIdentifier)
    }

    Connections {
        target: embyBackend

        function onPlexPinReady(pinCode, url) {
            plexRoot.code = pinCode || ""
            plexRoot.linkUrl = url || "https://plex.tv/link"
            plexRoot.statusText = "ENTER CODE"
            plexRoot.errorMessage = ""
            plexRoot.waitingForApproval = true
            pollTimer.restart()
        }

        function onPlexServersLoaded(items) {
            plexRoot.waitingForApproval = false
            plexRoot.servers = items || []
            plexRoot.serverIndex = 0
            plexRoot.statusText = "SELECT PLEX SERVER"
            serverList.forceActiveFocus()
        }

        function onAuthSuccess() {
            pollTimer.stop()
            plexRoot.waitingForApproval = false
            plexRoot.replaceWith("Libraries.qml", {})
        }

        function onErrorOccurred(msg) {
            plexRoot.errorMessage = msg || "PLEX SIGN IN FAILED"
            plexRoot.statusText = "PLEX ERROR"
            plexRoot.waitingForApproval = false
        }
    }

    Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        running: plexRoot.waitingForApproval && plexRoot.code !== ""
        onTriggered: embyBackend.poll_plex_pin_login()
    }

    Component.onCompleted: begin()
    Component.onDestruction: pollTimer.stop()

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
            plexRoot.goBack()
            event.accepted = true
            return
        }

        if (servers.length > 0) {
            if (event.key === Qt.Key_Up) {
                serverIndex = Math.max(0, serverIndex - 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                serverIndex = Math.min(servers.length - 1, serverIndex + 1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                selectServer()
                event.accepted = true
            }
        }
    }

    AppBar {
        iconSource: moduleRoot.moduleIcon
        title: moduleRoot.moduleName
        subtitle: "PLEX SIGN IN"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125
        anchors.leftMargin: root.sw * 0.125
    }

    Column {
        visible: servers.length === 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.245
        anchors.leftMargin: root.sw * 0.115625
        width: root.sw * 0.76875
        spacing: root.sh * 0.025

        Text {
            text: statusText
            color: root.secondaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            font.pixelSize: root.sh * 0.04
        }

        Text {
            text: code === "" ? "----" : code
            color: root.primaryColor
            font.family: root.globalFont
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            font.pixelSize: root.sh * 0.14
        }

        Text {
            text: linkUrl
            color: root.accentColor
            font.family: root.globalFont
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            elide: Text.ElideRight
            font.pixelSize: root.sh * 0.045
        }

        Text {
            visible: errorMessage !== ""
            text: errorMessage
            color: root.tertiaryColor
            font.family: root.globalFont
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            font.pixelSize: root.sh * 0.033
        }
    }

    ListView {
        id: serverList
        visible: servers.length > 0
        model: servers
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.25
        anchors.leftMargin: root.sw * 0.115625
        width: root.sw * 0.76875
        height: root.sh * 0.525
        clip: true
        focus: visible
        currentIndex: plexRoot.serverIndex
        onCurrentIndexChanged: plexRoot.serverIndex = currentIndex

        delegate: Item {
            width: serverList.width
            height: root.sh * 0.07

            Rectangle {
                anchors.fill: serverName
                color: root.accentColor
                visible: serverList.currentIndex === index
            }

            Text {
                id: serverName
                text: (modelData.name || "PLEX SERVER") + (modelData.local ? "  LOCAL" : "")
                color: serverList.currentIndex === index ? root.surfaceColor : root.primaryColor
                font.family: root.globalFont
                font.capitalization: Font.AllUppercase
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                leftPadding: root.sw * 0.009375
                rightPadding: root.sw * 0.009375
                font.pixelSize: root.sh * 0.05
            }
        }
    }
}
