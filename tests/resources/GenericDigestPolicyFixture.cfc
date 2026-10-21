component extends="DigestPolicyFixture" accessors="true" {

    property name="transferAllowed" default="true";

    boolean function canTransfer(
        notifiable,
        sourceDefinition,
        destinationDefinition,
        items
    ) {
        return variables.transferAllowed;
    }

}
