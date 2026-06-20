#pragma once

#include <QObject>
#include <QByteArray>
#include <QHash>
#include <QHostAddress>
#include <QJsonObject>

class MpvController;
class QTcpServer;
class QTcpSocket;

class ControlApiServer : public QObject {
    Q_OBJECT

public:
    explicit ControlApiServer(MpvController *player, QObject *parent = nullptr);

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
    QString normalizedKey(const QString &key) const;
    void pressKey(const QString &key, int repeat = 1);
    void writeJson(QTcpSocket *socket, int statusCode, const QJsonObject &body) const;
    void writeEmpty(QTcpSocket *socket, int statusCode) const;

    MpvController *m_player = nullptr;
    QTcpServer *m_server = nullptr;
    QHash<QTcpSocket *, QByteArray> m_buffers;
    QByteArray m_token;
};
