component accessors="true" {

    property name="id";
    property name="type" default="User";
    function init( string id = createUUID(), string type = "User" ) {
        variables.id = arguments.id;
        variables.type = arguments.type;
        return this;
    }
    string function getNotifiableId() {
        return variables.id;
    }
    string function getNotifiableType() {
        return variables.type;
    }

}
