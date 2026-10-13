/** A captured admission. Restoring it does not reevaluate recipients or preferences. */
component accessors="true" {

    property name="event" setter="false";
    property name="deliveries" setter="false";
    property name="admitAfter" setter="false";
    property name="queueOptions" setter="false";

    /**
     * Copies captured event, delivery, admission-cutoff, and queue-routing data; empty values support memento restoration.
     * @returns NotificationPlan
     */
    public NotificationPlan function init(
        struct event = {},
        array deliveries = [],
        any admitAfter,
        struct queueOptions = {}
    ) {
        return configure( argumentCollection = arguments );
    }

    /**
     * Configures the NotificationPlan after WireBox constructs and injects it.
     * @returns NotificationPlan
     */
    public NotificationPlan function configure(
        struct event = {},
        array deliveries = [],
        any admitAfter,
        struct queueOptions = {}
    ) {
        variables.queueOptions = duplicate( arguments.queueOptions );
        variables.event = duplicate( arguments.event );
        variables.deliveries = duplicate( arguments.deliveries );
        structDelete( variables, "admitAfter" );
        if ( !isNull( arguments.admitAfter ) ) {
            variables.admitAfter = arguments.admitAfter;
        }
        return this;
    }

    /**
     * Restores a versioned plan without recalculating its audience, channels, hashes, or queue routing.
     * @returns NotificationPlan
     */
    public NotificationPlan function populateFromMemento( required struct memento ) {
        if (
            ( arguments.memento.schemaVersion ?: 0 ) != 1 || !isStruct( arguments.memento.event ?: "" ) || !isArray(
                arguments.memento.deliveries ?: ""
            )
        ) {
            throw( type = "Megaphone.Notification.InvalidPlan", message = "A version 1 notification plan is required." );
        }
        variables.queueOptions = duplicate( arguments.memento.queueOptions ?: {} );
        variables.event = duplicate( arguments.memento.event );
        variables.deliveries = duplicate( arguments.memento.deliveries );
        if ( !isNull( variables.event.createdDate ) ) {
            variables.event.createdDate = parseDateTime( variables.event.createdDate );
        }
        for ( var intent in variables.deliveries ) {
            if ( !isNull( intent.availableDate ) ) {
                intent.availableDate = parseDateTime( intent.availableDate );
            }
        }
        structDelete( variables, "admitAfter" );
        if ( !isNull( arguments.memento.admitAfter ) ) {
            variables.admitAfter = parseDateTime( arguments.memento.admitAfter );
        }
        return this;
    }

    /**
     * Returns the event data represented by this object.
     * @returns struct
     */
    public struct function getEvent() {
        return duplicate( variables.event );
    }
    /**
     * Returns the deliveries represented by this object.
     * @returns array
     */
    public array function getDeliveries() {
        return duplicate( variables.deliveries );
    }

    /**
     * Returns a copy of the connection and queue choices captured with this plan.
     * @returns struct
     */
    public struct function getQueueOptions() {
        return duplicate( variables.queueOptions );
    }

    /**
     * Returns the versioned plan data needed to restore the original delivery decisions.
     * @returns struct
     */
    public struct function getMemento() {
        var result = {
            "schemaVersion": 1,
            "event": duplicate( variables.event ),
            "deliveries": duplicate( variables.deliveries )
        };
        if ( !variables.queueOptions.isEmpty() ) {
            result.queueOptions = duplicate( variables.queueOptions );
        }
        if ( !isNull( variables.admitAfter ) ) {
            result.admitAfter = variables.admitAfter;
        }
        return result;
    }

}
