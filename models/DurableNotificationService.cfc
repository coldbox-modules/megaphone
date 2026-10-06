/** Opt-in transaction boundary. Queue adapters enqueue references; providers execute after commit. */
component singleton {

    property name="eventStore" inject="EventStore@megaphone";
    property name="deliveryStore" inject="DeliveryStore@megaphone";

    public boolean function canPublish( required date occurredAt, required date admitAfter ) {
        return dateCompare( arguments.occurredAt, arguments.admitAfter ) >= 0;
    }

    public struct function publish(
        required struct event,
        required array intents,
        any queueAdapter,
        date admitAfter
    ) {
        if ( !isNull( arguments.admitAfter ) ) {
            if ( !structKeyExists( arguments.event, "createdDate" ) || !isDate( arguments.event.createdDate ) ) {
                throw(
                    type = "Megaphone.Events.OccurrenceRequired",
                    message = "Bounded publication requires a persisted event occurrence time."
                );
            }
            if ( !canPublish( arguments.event.createdDate, arguments.admitAfter ) ) {
                return { "event": { "id": "", "created": false, "expired": true }, "deliveries": [] };
            }
        }
        transaction {
            try {
                var recorded = variables.eventStore.record( argumentCollection = arguments.event );
                if ( !recorded.created ) {
                    // Replays must not add recipients/channels after an access or preference change.
                    return { "event": recorded, "deliveries": variables.deliveryStore.forEvent( recorded.id ) };
                }
                var deliveries = [];
                for ( var intent in arguments.intents ) {
                    if ( !isStruct( intent ) || !structKeyExists( intent, "enabled" ) || !isBoolean( intent.enabled ) ) {
                        throw(
                            type = "Megaphone.Delivery.InvalidIntent",
                            message = "Every planned delivery needs an explicit channel preference."
                        );
                    }
                    var delivery = variables.deliveryStore.enqueue(
                        eventId = recorded.id,
                        recipientType = intent.recipientType,
                        recipientId = intent.recipientId,
                        channel = intent.channel,
                        deviceId = intent.deviceId ?: "",
                        routingData = intent.routingData,
                        routingHash = intent.routingHash,
                        initialState = intent.enabled ? "queued" : "suppressed",
                        availableDate = intent.availableDate ?: now()
                    );
                    deliveries.append( delivery );
                    if ( delivery.created && delivery.state == "queued" && !isNull( arguments.queueAdapter ) ) {
                        arguments.queueAdapter.enqueue( delivery );
                    }
                }
                return { "event": recorded, "deliveries": deliveries };
            } catch ( any error ) {
                // A caller may catch publication errors inside its domain transaction.
                // Never leave an event committed without its intended delivery work.
                transactionRollback();
                rethrow;
            }
        }
    }

}
