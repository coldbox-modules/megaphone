/** Application callbacks provide current authorization/content and normalized transport results. */
component singleton {

    property name="deliveryStore" inject="DeliveryStore@megaphone";

    public string function dispatch(
        required string id,
        required function eligibility,
        required function sender,
        numeric leaseSeconds = 60,
        numeric maxAttempts = 5,
        numeric retrySeconds = 30
    ) {
        if ( arguments.retrySeconds < 1 || fix( arguments.retrySeconds ) != arguments.retrySeconds ) {
            throw( type = "Megaphone.Delivery.InvalidRetry", message = "Retry delay must be a positive integer." );
        }
        var claimed = variables.deliveryStore.claim(
            id = arguments.id,
            leaseSeconds = arguments.leaseSeconds,
            maxAttempts = arguments.maxAttempts
        );
        if ( claimed.status != "ready" ) {
            return claimed.status;
        }
        var ready = {};
        try {
            ready = arguments.eligibility( claimed.delivery );
            if ( !isStruct( ready ) || !listFind( "ready,suppressed,deferred,permanent", ready.status ?: "" ) ) {
                throw(
                    type = "Megaphone.Delivery.InvalidEligibility",
                    message = "Eligibility must return a supported status."
                );
            }
        } catch ( any error ) {
            variables.deliveryStore.complete(
                id = arguments.id,
                token = claimed.token,
                outcome = "retryable",
                reason = "eligibility-error",
                retryDate = dateAdd( "s", arguments.retrySeconds, now() )
            );
            return "retryable";
        }
        if ( ready.status != "ready" ) {
            var outcome = ready.status == "deferred" ? "retryable" : ready.status;
            return variables.deliveryStore.complete(
                id = arguments.id,
                token = claimed.token,
                outcome = outcome,
                reason = ready.reason ?: ready.status,
                retryDate = ready.retryDate ?: dateAdd( "s", arguments.retrySeconds, now() )
            ) ? outcome : "superseded";
        }
        if ( !variables.deliveryStore.startTransport( arguments.id, claimed.token ) ) {
            return "superseded";
        }
        var result = {};
        try {
            result = arguments.sender( claimed.delivery, ready );
            if ( !isStruct( result ) || !listFind( "accepted,retryable,permanent,ambiguous", result.outcome ?: "" ) ) {
                throw(
                    type = "Megaphone.Delivery.InvalidTransportResult",
                    message = "Transport must return a normalized outcome."
                );
            }
        } catch ( any error ) {
            // Once I/O starts an exception cannot establish that the provider rejected it.
            result = { "outcome": "ambiguous", "reason": "provider-outcome-unknown" };
        }
        return variables.deliveryStore.complete(
            id = arguments.id,
            token = claimed.token,
            outcome = result.outcome,
            reason = result.reason ?: "",
            providerReference = result.providerReference ?: "",
            retryDate = result.retryDate ?: dateAdd( "s", arguments.retrySeconds, now() )
        ) ? result.outcome : "superseded";
    }

}
