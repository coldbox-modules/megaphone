component accessors="true" {

    property name="consent" default="true";
    property name="admission" default="true";
    property name="excluded";
    function init() {
        variables.excluded = {};
        return this;
    }
    boolean function canCollect( notifiable, definition, item ) {
        return variables.admission && variables.consent;
    }
    boolean function canSend( notifiable, definition, subscription ) {
        return variables.consent;
    }
    boolean function isEligible( notifiable, definition, item ) {
        return !structKeyExists( variables.excluded, item.itemKey );
    }

}
