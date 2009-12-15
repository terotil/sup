Sup Protocol
============

Requests
--------

There may be zero or more replies to a request. Multiple requests may be
issued concurrently. `tag` is an opaque object returned in all replies to
the request.

### Query

Send a Message reply for each hit on `query`. `offset` and `limit`
influence which results are returned.

#### Parameters
*   `tag`: opaque object
*   `query`: Xapian query string
*   `offset`: skip this many messages
*   `limit`: return at most this many messages
*   `raw:` include the raw message text

#### Responses
*   multiple Message
*   one Done after all Messages

### Count

Send a count reply with the number of hits for `query`.

#### Parameters
*   `tag`: opaque object
*   `query`: Xapian query string

#### Responses
*   one Count

### Label

Modify the labels on all messages matching `query`.

#### Parameters
*   `tag`: opaque object
*   `query`: Xapian query string
*   `add`: labels to add
*   `remove`: labels to remove

#### Responses
*   one Done

### Add

Add a message to the database. `raw` is the normal RFC 2822 message text.

#### Parameters
*   `tag`: opaque object
*   `raw`: message data
*   `labels`: initial labels

#### Responses
*   one Done

### Stream

#### Parameters
*   `tag`: opaque object
*   `query`: Xapian query string

#### Responses
multiple Message

### Cancel

#### Parameters
*   `tag`: opaque object
*   `target`: tag of the request to cancel

#### Responses
one Done

Responses
---------

### Done

#### Parameters
*   `tag`: opaque object

### Message

#### Parameters
*   `tag`: opaque object
*   `message`:
  *   `message_id`
  *   `date`
  *   `from`
  *   `to`, `cc`, `bcc`: List of [`email`, `name`]
  *   `subject`
  *   `refs`
  *   `replytos`
  *   `labels`

### Count

#### Parameters
*   `tag`: opaque object
*   `count`: number of messages matched

### Error

#### Parameters
*   `tag`: opaque object
*   `type`: symbol
*   `message`: string
