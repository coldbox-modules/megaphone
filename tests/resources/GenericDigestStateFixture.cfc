component accessors="true" {

    property name="channels";
    property name="onFormat";
    property name="formatted";

    function init() {
        variables.channels = [ "summaryEmail", "summarySMS" ];
        variables.formatted = [];
        return this;
    }

}
