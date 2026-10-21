/** Local, authoritative consent and item eligibility checks shared by all digest transports. */
interface extends="IEmailDigestPolicy" {

    // Optional transfer approval: canTransfer(notifiable, sourceDefinition, destinationDefinition, items).
    // A policy without that hook cannot accept transferred items.

}
