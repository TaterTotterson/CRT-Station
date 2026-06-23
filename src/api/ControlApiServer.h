#pragma once

#include <QObject>
#include <QByteArray>
#include <QHash>
#include <QHostAddress>
#include <QJsonObject>
#include <QVariantMap>

class MpvController;
class EmbyJellyfinBackend;
class RetroBackend;
class QTcpServer;
class QTcpSocket;
class QTimer;

class ControlApiServer : public QObject {
    Q_OBJECT

public:
    explicit ControlApiServer(MpvController *player,
                              EmbyJellyfinBackend *mediaBackend = nullptr,
                              RetroBackend *retroBackend = nullptr,
                              QObject *parent = nullptr);

    bool startFromEnvironment();
    bool start(const QHostAddress &address, quint16 port);

private:
    struct HttpRequest {
        QByteArray method;
        QString path;
        QHash<QByteArray, QByteArray> headers;
        QByteArray body;
    };

    void onNewConnection();
    void onReadyRead(QTcpSocket *socket);
    bool tryParseRequest(const QByteArray &buffer, HttpRequest &request) const;
    void handleRequest(QTcpSocket *socket, const HttpRequest &request);

    bool isAuthorized(const HttpRequest &request) const;
    QJsonObject playbackStatus() const;
    QJsonObject parseBodyObject(const HttpRequest &request, bool &ok) const;
    void handleSearchRequest(QTcpSocket *socket, const HttpRequest &request);
    void handleLaunchRequest(QTcpSocket *socket, const HttpRequest &request);
    QString normalizedKey(const QString &key) const;
    void pressKey(const QString &key, int repeat = 1);
    QStringList requestedTypes(const QJsonObject &body) const;
    bool wantsGames(const QStringList &types) const;
    bool wantsMedia(const QStringList &types) const;
    QString percentDecode(const QString &value) const;
    void launchMedia(QTcpSocket *socket, const QString &ratingKey, const QString &kind);
    void launchGame(QTcpSocket *socket, const QString &systemId, const QString &path);
    void startApiTimeline(const QVariantMap &launch);
    void stopApiTimeline(int finalPositionMs, int finalDurationMs);
    void sendApiTimeline(const QString &state, int positionMs = -1, int durationMs = -1);
    void writeJson(QTcpSocket *socket, int statusCode, const QJsonObject &body) const;
    void writeEmpty(QTcpSocket *socket, int statusCode) const;

    MpvController *m_player = nullptr;
    EmbyJellyfinBackend *m_mediaBackend = nullptr;
    RetroBackend *m_retroBackend = nullptr;
    QTcpServer *m_server = nullptr;
    QTimer *m_apiTimelineTimer = nullptr;
    QHash<QTcpSocket *, QByteArray> m_buffers;
    QByteArray m_token;
    QString m_apiTimelineRatingKey;
    QString m_apiTimelinePartKey;
};
