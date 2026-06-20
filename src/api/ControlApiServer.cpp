#include "ControlApiServer.h"

#include "../player/MpvController.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonValue>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUrl>
#include <QDebug>
#include <algorithm>

namespace {
constexpr qsizetype MaxHeaderBytes = 16 * 1024;
constexpr qsizetype MaxBodyBytes = 64 * 1024;

QByteArray statusText(int statusCode) {
    switch (statusCode) {
    case 200: return "OK";
    case 204: return "No Content";
    case 400: return "Bad Request";
    case 401: return "Unauthorized";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 409: return "Conflict";
    case 413: return "Payload Too Large";
    default: return "Internal Server Error";
    }
}

int jsonInt(const QJsonObject &obj, const char *key, int fallback) {
    const QJsonValue value = obj.value(QString::fromLatin1(key));
    return value.isDouble() ? value.toInt() : fallback;
}

double jsonDouble(const QJsonObject &obj, const char *key, double fallback) {
    const QJsonValue value = obj.value(QString::fromLatin1(key));
    return value.isDouble() ? value.toDouble() : fallback;
}
} // namespace

ControlApiServer::ControlApiServer(MpvController *player, QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_server(new QTcpServer(this))
{
    connect(m_server, &QTcpServer::newConnection, this, &ControlApiServer::onNewConnection);
}

bool ControlApiServer::startFromEnvironment() {
    bool ok = false;
    const int enabled = qEnvironmentVariableIntValue("MP240_API_ENABLED", &ok);
    if (ok && enabled == 0) {
        qInfo("[ControlApi] disabled by MP240_API_ENABLED=0");
        return false;
    }

    const QString host = qEnvironmentVariable("MP240_API_HOST", QStringLiteral("0.0.0.0"));
    const int envPort = qEnvironmentVariableIntValue("MP240_API_PORT", &ok);
    const int port = ok ? envPort : 24024;
    if (port <= 0 || port > 65535) {
        qWarning("[ControlApi] invalid MP240_API_PORT=%d", port);
        return false;
    }

    QHostAddress address;
    if (host.isEmpty() || host == QStringLiteral("*") || host == QStringLiteral("0.0.0.0")) {
        address = QHostAddress::Any;
    } else if (!address.setAddress(host)) {
        qWarning("[ControlApi] invalid MP240_API_HOST=%s", qPrintable(host));
        return false;
    }

    m_token = qgetenv("MP240_API_TOKEN").trimmed();
    return start(address, quint16(port));
}

bool ControlApiServer::start(const QHostAddress &address, quint16 port) {
    if (m_server->isListening())
        m_server->close();

    if (!m_server->listen(address, port)) {
        qWarning("[ControlApi] listen failed on %s:%u: %s",
                 qPrintable(address.toString()), unsigned(port),
                 qPrintable(m_server->errorString()));
        return false;
    }

    qInfo("[ControlApi] listening on %s:%u%s",
          qPrintable(address.toString()), unsigned(m_server->serverPort()),
          m_token.isEmpty() ? " without token" : " with token");
    return true;
}

void ControlApiServer::onNewConnection() {
    while (QTcpSocket *socket = m_server->nextPendingConnection()) {
        connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
            onReadyRead(socket);
        });
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QObject::destroyed, this, [this, socket]() {
            m_buffers.remove(socket);
        });
    }
}

void ControlApiServer::onReadyRead(QTcpSocket *socket) {
    QByteArray &buffer = m_buffers[socket];
    buffer += socket->readAll();

    if (buffer.size() > MaxHeaderBytes + MaxBodyBytes) {
        writeJson(socket, 413, {{"ok", false}, {"error", "payload_too_large"}});
        return;
    }

    HttpRequest request;
    if (!tryParseRequest(buffer, request))
        return;

    m_buffers.remove(socket);
    handleRequest(socket, request);
}

bool ControlApiServer::tryParseRequest(const QByteArray &buffer, HttpRequest &request) const {
    const qsizetype headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd < 0)
        return false;
    if (headerEnd > MaxHeaderBytes)
        return false;

    const QList<QByteArray> lines = buffer.left(headerEnd).split('\n');
    if (lines.isEmpty())
        return false;

    const QList<QByteArray> requestLine = lines.first().trimmed().split(' ');
    if (requestLine.size() < 3)
        return false;

    request.method = requestLine.at(0).trimmed().toUpper();
    const QUrl url(QString::fromUtf8(requestLine.at(1)));
    request.path = url.path().isEmpty() ? QStringLiteral("/") : url.path();

    int contentLength = 0;
    for (int i = 1; i < lines.size(); ++i) {
        const QByteArray line = lines.at(i).trimmed();
        const qsizetype colon = line.indexOf(':');
        if (colon <= 0)
            continue;
        const QByteArray key = line.left(colon).trimmed().toLower();
        const QByteArray value = line.mid(colon + 1).trimmed();
        request.headers.insert(key, value);
        if (key == "content-length") {
            bool ok = false;
            contentLength = value.toInt(&ok);
            if (!ok || contentLength < 0 || contentLength > MaxBodyBytes)
                return false;
        }
    }

    const qsizetype bodyStart = headerEnd + 4;
    if (buffer.size() < bodyStart + contentLength)
        return false;

    request.body = buffer.mid(bodyStart, contentLength);
    return true;
}

void ControlApiServer::handleRequest(QTcpSocket *socket, const HttpRequest &request) {
    if (request.method == "OPTIONS") {
        writeEmpty(socket, 204);
        return;
    }

    if (!isAuthorized(request)) {
        writeJson(socket, 401, {{"ok", false}, {"error", "unauthorized"}});
        return;
    }

    if (request.method == "GET" && request.path == QStringLiteral("/api/v1/status")) {
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.method != "POST") {
        writeJson(socket, 405, {{"ok", false}, {"error", "method_not_allowed"}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/stop")) {
        m_player->stop();
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (!m_player->isRunning()) {
        writeJson(socket, 409, {{"ok", false}, {"error", "player_not_running"},
                                {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/play-pause") ||
        request.path == QStringLiteral("/api/v1/player/pause-toggle")) {
        m_player->togglePause();
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/pause")) {
        m_player->setPaused(true);
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/resume")) {
        m_player->setPaused(false);
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/volume-up")) {
        pressKey(QStringLiteral("VOLUME_UP"));
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/volume-down")) {
        pressKey(QStringLiteral("VOLUME_DOWN"));
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/mute")) {
        pressKey(QStringLiteral("MUTE"));
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/skip-forward") ||
        request.path == QStringLiteral("/api/v1/player/skip-back")) {
        bool ok = false;
        const QJsonObject body = parseBodyObject(request, ok);
        if (!ok) {
            writeJson(socket, 400, {{"ok", false}, {"error", "invalid_json"}});
            return;
        }
        const int defaultOffset = request.path.endsWith(QStringLiteral("skip-forward")) ? 30000 : -10000;
        const int offsetMs = jsonInt(body, "offset_ms", defaultOffset);
        const int target = std::max(0, m_player->position() + offsetMs);
        m_player->seekTo(target);
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/seek")) {
        bool ok = false;
        const QJsonObject body = parseBodyObject(request, ok);
        if (!ok) {
            writeJson(socket, 400, {{"ok", false}, {"error", "invalid_json"}});
            return;
        }

        int targetMs = -1;
        if (body.contains(QStringLiteral("position_ms"))) {
            targetMs = jsonInt(body, "position_ms", -1);
        } else if (body.contains(QStringLiteral("position_seconds"))) {
            targetMs = int(jsonDouble(body, "position_seconds", -1.0) * 1000.0);
        } else if (body.contains(QStringLiteral("offset_ms"))) {
            targetMs = m_player->position() + jsonInt(body, "offset_ms", 0);
        } else if (body.contains(QStringLiteral("offset_seconds"))) {
            targetMs = m_player->position() + int(jsonDouble(body, "offset_seconds", 0.0) * 1000.0);
        }

        if (targetMs < 0) {
            writeJson(socket, 400, {{"ok", false}, {"error", "missing_seek_target"}});
            return;
        }
        if (m_player->duration() > 0)
            targetMs = std::min(targetMs, m_player->duration());
        m_player->seekTo(std::max(0, targetMs));
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    if (request.path == QStringLiteral("/api/v1/player/key")) {
        bool ok = false;
        const QJsonObject body = parseBodyObject(request, ok);
        if (!ok) {
            writeJson(socket, 400, {{"ok", false}, {"error", "invalid_json"}});
            return;
        }
        const QString key = normalizedKey(body.value(QStringLiteral("key")).toString());
        if (key.isEmpty()) {
            writeJson(socket, 400, {{"ok", false}, {"error", "unsupported_key"}});
            return;
        }
        const int repeat = std::max(1, std::min(jsonInt(body, "repeat", 1), 20));
        pressKey(key, repeat);
        writeJson(socket, 200, {{"ok", true}, {"status", playbackStatus()}});
        return;
    }

    writeJson(socket, 404, {{"ok", false}, {"error", "not_found"}});
}

bool ControlApiServer::isAuthorized(const HttpRequest &request) const {
    if (m_token.isEmpty())
        return true;

    const QByteArray auth = request.headers.value("authorization");
    if (auth == QByteArray("Bearer ") + m_token)
        return true;

    return request.headers.value("x-240mp-token") == m_token;
}

QJsonObject ControlApiServer::playbackStatus() const {
    return {
        {"app", QJsonObject{
            {"name", QCoreApplication::applicationName()},
            {"version", QCoreApplication::applicationVersion()}
        }},
        {"playback", QJsonObject{
            {"running", m_player && m_player->isRunning()},
            {"paused", m_player && m_player->paused()},
            {"position_ms", m_player ? m_player->position() : 0},
            {"duration_ms", m_player ? m_player->duration() : 0},
            {"playlist_pos", m_player ? m_player->playlistPos() : -1}
        }}
    };
}

QJsonObject ControlApiServer::parseBodyObject(const HttpRequest &request, bool &ok) const {
    ok = false;
    if (request.body.trimmed().isEmpty()) {
        ok = true;
        return {};
    }

    const QJsonDocument doc = QJsonDocument::fromJson(request.body);
    if (!doc.isObject())
        return {};

    ok = true;
    return doc.object();
}

QString ControlApiServer::normalizedKey(const QString &key) const {
    QString normalized = key.trimmed().toUpper();
    normalized.replace('-', '_');
    normalized.replace(' ', '_');

    static const QHash<QString, QString> aliases = {
        {QStringLiteral("OK"), QStringLiteral("ENTER")},
        {QStringLiteral("SELECT"), QStringLiteral("ENTER")},
        {QStringLiteral("BACK"), QStringLiteral("BS")},
        {QStringLiteral("BACKSPACE"), QStringLiteral("BS")},
        {QStringLiteral("EXIT"), QStringLiteral("ESC")},
        {QStringLiteral("PLAY"), QStringLiteral("SPACE")},
        {QStringLiteral("PAUSE"), QStringLiteral("SPACE")},
        {QStringLiteral("PLAY_PAUSE"), QStringLiteral("SPACE")},
        {QStringLiteral("PLAYPAUSE"), QStringLiteral("SPACE")},
        {QStringLiteral("VOL_UP"), QStringLiteral("VOLUME_UP")},
        {QStringLiteral("VOLUMEUP"), QStringLiteral("VOLUME_UP")},
        {QStringLiteral("VOL_DOWN"), QStringLiteral("VOLUME_DOWN")},
        {QStringLiteral("VOLUMEDOWN"), QStringLiteral("VOLUME_DOWN")},
        {QStringLiteral("SILENCE"), QStringLiteral("MUTE")}
    };
    normalized = aliases.value(normalized, normalized);

    static const QList<QString> allowed = {
        QStringLiteral("UP"),
        QStringLiteral("DOWN"),
        QStringLiteral("LEFT"),
        QStringLiteral("RIGHT"),
        QStringLiteral("ENTER"),
        QStringLiteral("ESC"),
        QStringLiteral("BS"),
        QStringLiteral("SPACE"),
        QStringLiteral("VOLUME_UP"),
        QStringLiteral("VOLUME_DOWN"),
        QStringLiteral("MUTE")
    };
    return allowed.contains(normalized) ? normalized : QString();
}

void ControlApiServer::pressKey(const QString &key, int repeat) {
    for (int i = 0; i < repeat; ++i)
        m_player->sendKey(key);
}

void ControlApiServer::writeJson(QTcpSocket *socket, int statusCode, const QJsonObject &body) const {
    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    QByteArray response;
    response += "HTTP/1.1 " + QByteArray::number(statusCode) + " " + statusText(statusCode) + "\r\n";
    response += "Content-Type: application/json; charset=utf-8\r\n";
    response += "Content-Length: " + QByteArray::number(payload.size()) + "\r\n";
    response += "Connection: close\r\n";
    response += "Access-Control-Allow-Origin: *\r\n";
    response += "Access-Control-Allow-Headers: Authorization, Content-Type, X-240MP-Token\r\n";
    response += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n";
    response += "\r\n";
    response += payload;
    socket->write(response);
    socket->disconnectFromHost();
}

void ControlApiServer::writeEmpty(QTcpSocket *socket, int statusCode) const {
    QByteArray response;
    response += "HTTP/1.1 " + QByteArray::number(statusCode) + " " + statusText(statusCode) + "\r\n";
    response += "Content-Length: 0\r\n";
    response += "Connection: close\r\n";
    response += "Access-Control-Allow-Origin: *\r\n";
    response += "Access-Control-Allow-Headers: Authorization, Content-Type, X-240MP-Token\r\n";
    response += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n";
    response += "\r\n";
    socket->write(response);
    socket->disconnectFromHost();
}
