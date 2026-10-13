component {

    function init( required string jarPath ) {
        variables.jarPath = arguments.jarPath;
        return this;
    }
    function create( required string className ) {
        if ( structKeyExists( server, "lucee" ) ) {
            return createObject( "java", arguments.className, variables.jarPath );
        }
        return createObject( "java", arguments.className );
    }

}
