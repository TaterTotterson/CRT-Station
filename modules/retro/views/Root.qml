import QtQuick
import Components

FocusScope {
    id: retroRoot

    signal goBack()

    property var navParams: ({})
    property string moduleId: "com.240mp.retro"
    property var _moduleInfo: appCore.get_module_info(moduleId)
    property string moduleName: _moduleInfo.name || "GAME CENTER"
    property string moduleIcon: _moduleInfo.icon || ""

    property string mode: "loading"
    property string statusText: "LOADING GAME CENTER..."
    property var systems: []
    property var games: []
    property int currentSystemIndex: 0
    property int currentGameIndex: 0
    property int setupRow: 0
    property bool mounting: false
    property string selectedSystemId: ""
    property string selectedSystemTitle: ""

    focus: true

    function settingValue(key, fallback) {
        var value = appCore.get_setting(moduleId, key)
        if (value === undefined || value === null || value === "") return fallback
        return value
    }

    function focusSetupRow() {
        if (setupRow === 0) hostField.forceInputFocus()
        else if (setupRow === 1) shareField.forceInputFocus()
        else if (setupRow === 2) pathField.forceInputFocus()
        else if (setupRow === 3) userField.forceInputFocus()
        else if (setupRow === 4) passwordField.forceInputFocus()
        else connectButton.forceActiveFocus()
    }

    function setupPrevious() {
        if (setupRow > 0) {
            setupRow--
            focusSetupRow()
        }
    }

    function setupNext() {
        if (setupRow < 5) {
            setupRow++
            focusSetupRow()
        }
    }

    function showSetup(message) {
        var status = retroBackend.get_setup_status()
        hostField.text = status.host || "retronas.local"
        shareField.text = status.share || "mister"
        pathField.text = status.remotePath || "games"
        userField.text = status.username || ""
        passwordField.text = settingValue("retronas_password", "")
        statusText = message || "ENTER RETRONAS INFO"
        mounting = false
        mode = "setup"
        setupFocusTimer.restart()
    }

    function loadSystems() {
        mode = "loading"
        statusText = "LOADING GAME LIST..."
        retroBackend.load_systems()
    }

    function refresh() {
        var status = retroBackend.get_setup_status()
        if (!status.retroarchAvailable) {
            mode = "message"
            statusText = "RETROARCH IS NOT INSTALLED"
            return
        }
        if (!status.gamesRootExists) {
            showSetup("ENTER RETRONAS INFO")
            return
        }
        loadSystems()
    }

    function saveSetup() {
        if (mounting) return
        var host = (hostField.text || "").trim()
        var share = (shareField.text || "").trim()
        var remotePath = (pathField.text || "").trim()
        var username = (userField.text || "").trim()
        var password = passwordField.text || ""

        if (host === "") {
            statusText = "ENTER RETRONAS ADDRESS"
            setupRow = 0
            focusSetupRow()
            return
        }
        if (share === "") share = "mister"
        if (remotePath === "") remotePath = "games"

        appCore.save_setting(moduleId, "retronas_host", host)
        appCore.save_setting(moduleId, "retronas_share", share)
        appCore.save_setting(moduleId, "retronas_path", remotePath)
        appCore.save_setting(moduleId, "retronas_username", username)
        appCore.save_setting(moduleId, "retronas_password", password)

        mounting = true
        statusText = "MOUNTING RETRONAS..."
        retroBackend.mount_retronas(host, share, remotePath, username, password)
    }

    function selectSystem(index) {
        if (index < 0 || index >= systems.length) return
        currentSystemIndex = index
        systemList.currentIndex = index
        var system = systems[index] || ({})
        selectedSystemId = system.id || ""
        selectedSystemTitle = system.label || "RETRO"
        mode = "loading"
        statusText = "LOADING " + selectedSystemTitle
        retroBackend.load_games(selectedSystemId)
    }

    function launchSelectedGame() {
        var index = gameList.currentIndex
        if (index < 0 || index >= games.length) return
        currentGameIndex = index
        var game = games[index] || ({})
        var title = game.title || "GAME"
        statusText = "LOADING " + title
        mode = "loading"
        retroBackend.launch_game(selectedSystemId, game.path || "")
    }

    function pageGameList(direction) {
        if (games.length === 0) return
        var rowHeight = root.sh * 0.0583333
        var rows = Math.max(1, Math.floor(gameList.height / rowHeight) - 1)
        var next = Math.max(0, Math.min(gameList.count - 1, gameList.currentIndex + direction * rows))
        gameList.currentIndex = next
        currentGameIndex = next
        gameList.positionViewAtIndex(next, ListView.Contain)
    }

    Keys.onPressed: function(event) {
        if (mode === "setup") {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                goBack()
                event.accepted = true
            }
            return
        }

        if (mode === "systems") {
            if (event.key === Qt.Key_Up) {
                systemList.currentIndex = Math.max(0, systemList.currentIndex - 1)
                currentSystemIndex = systemList.currentIndex
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                systemList.currentIndex = Math.min(systemList.count - 1, systemList.currentIndex + 1)
                currentSystemIndex = systemList.currentIndex
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                selectSystem(systemList.currentIndex)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                goBack()
                event.accepted = true
            }
            return
        }

        if (mode === "games") {
            if (event.key === Qt.Key_Up) {
                gameList.currentIndex = Math.max(0, gameList.currentIndex - 1)
                currentGameIndex = gameList.currentIndex
                event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                gameList.currentIndex = Math.min(gameList.count - 1, gameList.currentIndex + 1)
                currentGameIndex = gameList.currentIndex
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                pageGameList(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                pageGameList(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                mode = "systems"
                systemList.currentIndex = currentSystemIndex
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                launchSelectedGame()
                event.accepted = true
            }
            return
        }

        if (mode === "message") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                refresh()
                event.accepted = true
            } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.key === Qt.Key_Back) {
                goBack()
                event.accepted = true
            }
        }
    }

    Component.onCompleted: refresh()

    Component.onDestruction: {
        if (retroBackend.running)
            retroBackend.stop_game()
    }

    Timer {
        id: setupFocusTimer
        interval: 1
        repeat: false
        onTriggered: focusSetupRow()
    }

    Connections {
        target: retroBackend

        function onMountFinished(ok, message) {
            mounting = false
            if (!ok) {
                statusText = message || "RETRONAS MOUNT FAILED"
                mode = "setup"
                setupFocusTimer.restart()
                return
            }
            loadSystems()
        }

        function onSystemsLoaded(items) {
            systems = items || []
            if (systems.length === 0) {
                mode = "message"
                statusText = "NO SUPPORTED ROM FOLDERS"
                return
            }
            mode = "systems"
            currentSystemIndex = Math.min(currentSystemIndex, systems.length - 1)
            systemList.currentIndex = currentSystemIndex
        }

        function onGamesLoaded(items) {
            games = items || []
            if (games.length === 0) {
                mode = "message"
                statusText = "NO ROMS IN " + selectedSystemTitle
                return
            }
            mode = "games"
            currentGameIndex = 0
            gameList.currentIndex = 0
        }

        function onGameStarted(title) {
            statusText = "PLAYING " + (title || "GAME")
            mode = "playing"
        }

        function onGameFinished() {
            if (mode === "playing" || mode === "loading")
                mode = games.length > 0 ? "games" : "systems"
        }

        function onErrorOccurred(message) {
            mode = "message"
            statusText = message || "RETRO PLAYBACK FAILED"
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
        subtitle: mode === "games" ? selectedSystemTitle : "MISTER"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.125
        anchors.leftMargin: root.sw * 0.125
    }

    Text {
        visible: mode === "loading" || mode === "message" || mode === "playing"
        text: mode === "playing" ? "GAME LOADING" : statusText
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
        id: setupForm
        visible: mode === "setup"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.22
        anchors.leftMargin: root.sw * 0.115625
        width: root.sw * 0.76875
        spacing: root.sh * 0.018

        Text {
            text: statusText
            color: root.secondaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: root.sh * 0.031
            width: setupForm.width
            elide: Text.ElideRight
        }

        SetupField {
            id: hostField
            label: "RETRONAS ADDRESS"
            selected: setupRow === 0
        }
        SetupField {
            id: shareField
            label: "SHARE"
            selected: setupRow === 1
        }
        SetupField {
            id: pathField
            label: "MISTER ROM PATH"
            selected: setupRow === 2
        }
        SetupField {
            id: userField
            label: "USERNAME"
            selected: setupRow === 3
        }
        SetupField {
            id: passwordField
            label: "PASSWORD"
            selected: setupRow === 4
            password: true
        }

        Rectangle {
            id: connectButton
            width: setupForm.width
            height: root.sh * 0.0583333
            color: setupRow === 5 ? root.accentColor : "transparent"
            focus: setupRow === 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: root.sw * 0.009375
                text: mounting ? "MOUNTING..." : "CONNECT"
                color: setupRow === 5 ? root.surfaceColor : root.primaryColor
                font.family: root.globalFont
                font.capitalization: Font.AllUppercase
                font.pixelSize: root.sh * 0.05
            }

            Keys.onUpPressed: setupPrevious()
            Keys.onDownPressed: setupNext()
            Keys.onReturnPressed: saveSetup()
            Keys.onEnterPressed: saveSetup()
        }
    }

    ListView {
        id: systemList
        visible: mode === "systems"
        model: systems
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.25
        anchors.leftMargin: root.sw * 0.115625
        width: root.sw * 0.76875
        height: root.sh * 0.525
        clip: true
        focus: visible
        onCurrentIndexChanged: currentSystemIndex = currentIndex

        delegate: Item {
            width: systemList.width
            height: root.sh * 0.0583333

            Rectangle {
                anchors.fill: systemText
                color: root.accentColor
                visible: systemList.currentIndex === index
            }

            Text {
                id: systemText
                text: (modelData.label || "SYSTEM") + "  " + (modelData.gameCount || 0)
                color: systemList.currentIndex === index ? root.surfaceColor : root.primaryColor
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

    ListView {
        id: gameList
        visible: mode === "games"
        model: games
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: root.sh * 0.25
        anchors.leftMargin: root.sw * 0.115625
        width: root.sw * 0.76875
        height: root.sh * 0.525
        clip: true
        focus: visible
        onCurrentIndexChanged: currentGameIndex = currentIndex

        delegate: Item {
            width: gameList.width
            height: root.sh * 0.0583333

            Rectangle {
                anchors.fill: gameText
                color: root.accentColor
                visible: gameList.currentIndex === index
            }

            Text {
                id: gameText
                text: modelData.title || "GAME"
                color: gameList.currentIndex === index ? root.surfaceColor : root.primaryColor
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

    component SetupField: Item {
        property alias text: fieldInput.text
        property string label: ""
        property bool selected: false
        property bool password: false

        function forceInputFocus() {
            fieldInput.forceActiveFocus()
        }

        width: setupForm.width
        height: root.sh * 0.076

        Rectangle {
            anchors.fill: parent
            color: selected ? root.accentColor : "transparent"
        }

        Text {
            id: fieldLabel
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: root.sw * 0.009375
            text: label
            color: selected ? root.surfaceColor : root.secondaryColor
            font.family: root.globalFont
            font.capitalization: Font.AllUppercase
            font.pixelSize: root.sh * 0.026
        }

        TextInput {
            id: fieldInput
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: fieldLabel.bottom
            anchors.leftMargin: root.sw * 0.009375
            anchors.rightMargin: root.sw * 0.009375
            height: root.sh * 0.044
            focus: selected
            echoMode: password ? TextInput.Password : TextInput.Normal
            color: selected ? root.surfaceColor : root.primaryColor
            selectedTextColor: root.surfaceColor
            selectionColor: root.tertiaryColor
            font.family: root.globalFont
            font.pixelSize: root.sh * 0.038
            clip: true

            Keys.onUpPressed: setupPrevious()
            Keys.onDownPressed: setupNext()
            Keys.onReturnPressed: setupNext()
            Keys.onEnterPressed: setupNext()
        }
    }
}
