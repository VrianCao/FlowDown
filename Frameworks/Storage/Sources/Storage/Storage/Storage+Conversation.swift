//
//  Storage+Conversation.swift
//  Storage
//
//  Created by 秋星桥 on 1/31/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func conversationList() -> [Conversation] {
        (
            try? db.getObjects(
                fromTable: Conversation.tableName,
                where: Conversation.Properties.removed == false,
                orderBy: [
                    Conversation.Properties.creation
                        .order(.descending),
                ]
            )
        ) ?? []
    }

    func conversationListAllIdentifiers() -> Set<Conversation.ID> {
        let identifiers = try? db.getColumn(
            on: Conversation.Properties.objectId,
            fromTable: Conversation.tableName,
            where: Conversation.Properties.removed == false
        )
        let items = identifiers?.map(\.stringValue) ?? []
        return .init(items)
    }

    typealias ConversationMakeInitDataBlock = (Conversation) -> Void
    func conversationMake(skipSave: Bool = false, _ block: ConversationMakeInitDataBlock?) -> Conversation {
        let object = Conversation(deviceId: Self.deviceId)
        if let block {
            block(object)
        }

        if skipSave {
            return object
        }

        try? runTransaction {
            try $0.insert([object], intoTable: Conversation.tableName)
            try self.pendingUploadEnqueue(sources: [(object, .insert)], handle: $0)
        }

        return object
    }

    func conversationUpdate(object: Conversation) {
        conversationUpdate(objects: [object])
    }

    func conversationUpdate(objects: [Conversation]) {
        guard !objects.isEmpty else {
            return
        }
        let modified = Date.now
        objects.forEach { $0.markModified(modified) }

        try? runTransaction { [weak self] in
            guard let self else { return }

            let diff = try diffSyncable(objects: objects, handle: $0)
            guard !diff.isEmpty else {
                return
            }

            /// 恢复修改时间
            diff.insert.forEach { $0.markModified($0.creation) }

            try $0.insertOrReplace(diff.insertOrReplace(), intoTable: Conversation.tableName)

            if !diff.deleted.isEmpty {
                let deletedIds = diff.deleted.map(\.objectId)
                let update = StatementUpdate().update(table: Conversation.tableName)
                    .set(Conversation.Properties.removed)
                    .to(true)
                    .set(Conversation.Properties.modified)
                    .to(modified)
                    .where(Conversation.Properties.objectId.in(deletedIds))

                try $0.exec(update)
            }

            var changes = diff.insert.map { ($0, UploadQueue.Changes.insert) }
                + diff.updated.map { ($0, UploadQueue.Changes.update) }
                + diff.deleted.map { ($0, UploadQueue.Changes.delete) }
            // 按 modified 升序
            changes.sort { $0.0.modified < $1.0.modified }

            try pendingUploadEnqueue(sources: changes, handle: $0)
        }
    }

    func conversationWith(identifier: Conversation.ID) -> Conversation? {
        try? db.getObject(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == identifier && Conversation.Properties.removed == false
        )
    }

    func conversationEdit(identifier: Conversation.ID, _ block: @escaping (inout Conversation) -> Void) {
        let read: Conversation? = try? db.getObject(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == identifier && Conversation.Properties.removed == false
        )
        guard var object = read else { return }
        block(&object)
        conversationUpdate(objects: [object])
    }

    func conversationRemove(conversationWith identifier: Conversation.ID) {
        guard !identifier.isEmpty else {
            return
        }

        try? runTransaction { [weak self] in
            guard let self else { return }
            try conversationMarkDelete(conversationId: identifier, handle: $0)
        }
    }

    @discardableResult
    func conversationDuplicate(identifier: Conversation.ID, customize: @escaping (Conversation) -> Void) -> Conversation.ID? {
        guard !identifier.isEmpty else {
            return nil
        }

        var ans: Conversation.ID?
        try? db.run { handler -> Bool in
            do {
                let ret = try self.executeDuplicationTransaction(
                    identifier: identifier,
                    handle: handler,
                    customize: customize
                )
                ans = ret
                return true
            } catch {
                assertionFailure(error.localizedDescription)
                return false
            }
        }
        return ans
    }

    private func executeDuplicationTransaction(
        identifier: Conversation.ID,
        handle: Handle,
        customize: (Conversation) -> Void
    ) throws -> Conversation.ID {
        let conv: Conversation? = try handle.getObject(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == identifier
        )
        guard let conv else { throw NSError() }

        // new objectId
        conv.objectId = UUID().uuidString
        conv.creation = .now
        conv.modified = .now

        customize(conv)
        try handle.insert([conv], intoTable: Conversation.tableName)

        let newIdentifier = conv.objectId
        guard newIdentifier != identifier else {
            assertionFailure()
            throw NSError()
        }

        var pendingUpload: [(source: any Syncable, changes: UploadQueue.Changes)] = [
            (conv, .insert),
        ]

        let messages: [Message] = try handle.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.conversationId == identifier,
            orderBy: [
                Message.Properties.creation.order(.ascending),
            ]
        )

        var oldMessageIdentifierSet = Set<String>()
        for message in messages {
            let oldMessageId = message.objectId
            oldMessageIdentifierSet.insert(oldMessageId)

            // new objectId
            message.objectId = UUID().uuidString
            message.conversationId = newIdentifier

            try handle.insert(message, intoTable: Message.tableName)
            let newMessageId = message.objectId

            var oldAttachmentIdentifierSet = Set<String>()
            let attachments: [Attachment] = try handle.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId == oldMessageId
            )
            for attachment in attachments {
                oldAttachmentIdentifierSet.insert(attachment.id)

                // new objectId
                attachment.objectId = UUID().uuidString
                attachment.messageId = message.objectId
                try handle.insert(attachment, intoTable: Attachment.tableName)
            }
            let newAttachments: [Attachment] = try handle.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId == newMessageId
            )

            for attachment in newAttachments {
                guard !oldAttachmentIdentifierSet.contains(attachment.id) else {
                    assertionFailure()
                    throw NSError()
                }
            }

            pendingUpload.append((message, .insert))
            pendingUpload.append(contentsOf: newAttachments.map { ($0, .insert) })
        }

        let newMessages: [Message] = try handle.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.conversationId == newIdentifier,
            orderBy: [
                Message.Properties.creation.order(.ascending),
            ]
        )

        for message in newMessages {
            guard !oldMessageIdentifierSet.contains(message.objectId) else {
                assertionFailure()
                throw NSError()
            }
        }

        try pendingUploadEnqueue(sources: pendingUpload, handle: handle)

        return newIdentifier
    }

    func conversationsDrop() {
        try? db.run { handle -> Bool in
            do {
                try self.executeEraseAllConversations(handle: handle)
                return true
            } catch {
                assertionFailure(error.localizedDescription)
                return false
            }
        }
    }

    func conversationMarkDelete(conversationId: Conversation.ID, handle: Handle? = nil) throws {
        guard !conversationId.isEmpty else {
            return
        }

        let conv: Conversation? = if let handle {
            try handle.getObject(fromTable: Conversation.tableName, where: Conversation.Properties.objectId == conversationId)
        } else {
            try db.getObject(fromTable: Conversation.tableName, where: Conversation.Properties.objectId == conversationId)
        }

        guard let conv else { return }

        let messages = listMessages(within: conversationId, handle: handle)
        let messagesIds = messages.compactMap(\.objectId)

        /// 删除操作不能恢复, 所以当删除会话后。可以不用同步对应的消息和附件
        try attachmentsMarkDelete(messageIds: messagesIds, skipSync: true, handle: handle)
        try messageMarkDelete(messageIds: messagesIds, skipSync: true, handle: handle)

        let update = StatementUpdate().update(table: Conversation.tableName)
            .set(Conversation.Properties.removed)
            .to(true)
            .set(Conversation.Properties.modified)
            .to(Date.now)
            .where(Conversation.Properties.objectId == conversationId)
        if let handle {
            try handle.exec(update)
        } else {
            try db.exec(update)
        }

        try pendingUploadEnqueue(sources: [(conv, .delete)], handle: handle)
    }

    func conversationMarkDelete(skipSync: Bool = false, handle: Handle? = nil) throws {
        let convs: [Conversation] = if let handle {
            try handle.getObjects(fromTable: Conversation.tableName, where: Conversation.Properties.removed == false, orderBy: [Conversation.Properties.modified.order(.ascending)])
        } else {
            try db.getObjects(fromTable: Conversation.tableName, where: Conversation.Properties.removed == false, orderBy: [Conversation.Properties.modified.order(.ascending)])
        }

        guard !convs.isEmpty else {
            return
        }

        let objectIds = convs.map(\.objectId)
        let update = StatementUpdate().update(table: Conversation.tableName)
            .set(Conversation.Properties.removed)
            .to(true)
            .set(Conversation.Properties.modified)
            .to(Date.now)
            .where(Conversation.Properties.objectId.in(objectIds))

        if let handle {
            try handle.exec(update)
        } else {
            try db.exec(update)
        }

        guard !skipSync else {
            return
        }

        try pendingUploadEnqueue(sources: convs.map { ($0, .delete) }, handle: handle)
    }

    private func executeEraseAllConversations(handle: Handle) throws {
        try conversationMarkDelete(handle: handle)

        /// 删除操作不能恢复, 所以当删除会话后。可以不用同步对应的消息和附件
        try messageMarkDelete(skipSync: true, handle: handle)
        try attachmentsMarkDelete(skipSync: true, handle: handle)
    }
}
