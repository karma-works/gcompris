/* GCompris - ClientNetworkMessagesStub.cpp
 *
 * SPDX-FileCopyrightText: 2026 GCompris contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

// No-op stub for Qt WebAssembly builds. QTcpSocket and QUdpSocket are not
// available in the browser sandbox, so teacher-server connectivity is disabled.

#include <QJsonObject>
#include <QAbstractSocket>
#include "ClientNetworkMessages.h"

ClientNetworkMessages::ClientNetworkMessages()
    : QObject()
    , _connected(false)
    , _missedPongs(0)
    , tcpSocket(nullptr)
    , udpSocket(nullptr)
    , status(netconst::NOT_CONNECTED)
    , pingTimer(this)
{
    userId = -1;
}

void ClientNetworkMessages::connectToServer(const QString &) {}
void ClientNetworkMessages::sendLoginMessage(const QString &, const QString &) {}
void ClientNetworkMessages::sendActivityData(const QString &, const QJsonObject &) {}
int  ClientNetworkMessages::connectionStatus() { return netconst::NOT_CONNECTED; }

void ClientNetworkMessages::readFromSocket() {}
void ClientNetworkMessages::udpRead() {}
void ClientNetworkMessages::connected() {}
void ClientNetworkMessages::onErrorOccurred(QAbstractSocket::SocketError) {}
void ClientNetworkMessages::serverDisconnected() {}
void ClientNetworkMessages::ping() {}
void ClientNetworkMessages::teacherPortChanged() {}

void      ClientNetworkMessages::disconnectFromServer() {}
void      ClientNetworkMessages::forgetUser() {}
QByteArray ClientNetworkMessages::prepareMessage(QJsonObject &) { return {}; }
void      ClientNetworkMessages::sendMessage(const QByteArray &) {}
void      ClientNetworkMessages::sendNextMessage() {}
bool      ClientNetworkMessages::sendStoredData() { return false; }
