# 0004 — Attachments

Status: draft
Brief: none

## Intent

A user should have an ability to add an attachment to an announcment (managers only) or to a message (managers and staff). An attachment might be a PDF files with some scheduling information, an image, an audio or a video file.

Not every attachment is allowed. Each attachment should be validated against its extension/content-type and size. Invalid attachments are rejected with a human-readably error message.

Maximum allowed size of as attachment is 10MB.
Allowed types are: `application/pdf`, `image/jpeg`, `image/png`, `image/webp`, `audio/mpeg`, `audio/mp4`, `video/mp4`.

A single announcement/message can have only one attachment.

## Acceptance criteria

1. A manager can add an attachment to their announcements and messages. A staff member can add an attachment to their messages.
2. Netither manager, nor user can add an invalid attachment (by size and/or content type).
3. In UI an attachment is rendered right next to its parent (visually underneath an announcement or a message).
4. Neither manager, not user cannot upload an attachment without a parent (without an announcement or a message).
5. Attachments are never hard-deleted.

## Out of scope

- Local-disk storage under a configured root; S3 or object storage out of scope.
- Thumbnails, resizing, transcoding.
- In-app voice recording.
- PDF previews.
